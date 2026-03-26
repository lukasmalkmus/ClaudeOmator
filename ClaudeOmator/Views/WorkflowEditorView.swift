import SwiftUI
import UniformTypeIdentifiers

struct WorkflowEditorView: View {
    @Binding var workflow: Workflow
    let engine: WorkflowEngine
    let store: WorkflowStore
    let activityStore: ActivityStore
    @Environment(NavigationState.self) private var navigationState
    @State private var showDirectoryPicker = false

    private let models = [
        ("Default", ""),
        ("Claude Sonnet 4.6", "claude-sonnet-4-6"),
        ("Claude Opus 4.6", "claude-opus-4-6"),
        ("Claude Haiku 4.5", "claude-haiku-4-5-20251001"),
    ]

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $workflow.name)
                Toggle("Enabled", isOn: $workflow.isEnabled)
                    .disabled(!workflow.isConfigured)
                Toggle("Notify on Completion", isOn: $workflow.notifyOnCompletion)
                groupPicker

                if !workflow.isConfigured {
                    Label {
                        Text(configurationHint)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }
            }

            Section("Trigger") {
                Picker("Type", selection: triggerTypeBinding) {
                    Text("Manual").tag(TriggerType.manual)
                    Text("Schedule").tag(TriggerType.schedule)
                }

                if case .schedule(let schedule) = workflow.trigger {
                    ScheduleEditorView(schedule: schedule) { newSchedule in
                        workflow.trigger = .schedule(newSchedule)
                    }

                    if workflow.isConfigured, let nextDate = schedule.nextFireDate() {
                        LabeledContent("Next") {
                            VStack(alignment: .trailing) {
                                Text("\(nextDate, format: .dateTime.weekday(.wide)), \(nextDate, style: .date) at \(nextDate, style: .time)")
                                Text(nextDate, style: .relative)
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Invocation") {
                TextEditor(text: $workflow.prompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if workflow.prompt.isEmpty {
                            Text("Prompt...")
                                .font(.body.monospaced())
                                .foregroundStyle(.placeholder)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                LabeledContent("Working Directory") {
                    HStack {
                        Text(workflow.workingDirectory ?? "Not set")
                            .foregroundStyle(workflow.workingDirectory == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
                            showDirectoryPicker = true
                        }
                        if workflow.workingDirectory != nil {
                            Button("Clear") {
                                workflow.workingDirectory = nil
                            }
                        }
                    }
                }

                Picker("Model", selection: modelBinding) {
                    ForEach(models, id: \.1) { name, value in
                        Text(name).tag(value)
                    }
                }

                Picker("Permission Mode", selection: permissionBinding) {
                    ForEach(PermissionMode.allCases) { mode in
                        Text(mode.label).tag(PermissionMode?.some(mode))
                    }
                }
            }

            Section("Recent Runs") {
                let runs = activityStore.entries(for: workflow.id).prefix(5)
                if runs.isEmpty {
                    Text("No runs yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(runs)) { entry in
                        Button {
                            navigationState.detailPath.append(
                                NavigationState.ActivityDestination(
                                    workflowID: workflow.id,
                                    runID: entry.id
                                )
                            )
                        } label: {
                            HStack {
                                Image(systemName: entry.status.systemImage)
                                    .foregroundStyle(entry.status.color)
                                Text("\(entry.completedAt ?? entry.startedAt, style: .relative) ago")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                workflow.workingDirectory = url.path
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if engine.isRunning(workflow.id) {
                    Button {
                        engine.cancel(workflow.id)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        engine.run(workflow)
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    .disabled(!workflow.isConfigured || !workflow.isEnabled || engine.claudeAvailable != true)
                }
            }
        }
    }

    private var configurationHint: String {
        let missingPrompt = workflow.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingDir = workflow.workingDirectory.map({ $0.isEmpty }) ?? true
        switch (missingPrompt, missingDir) {
        case (true, true): return "Set a prompt and working directory to enable this workflow."
        case (true, false): return "Set a prompt to enable this workflow."
        case (false, true): return "Set a working directory to enable this workflow."
        case (false, false): return ""
        }
    }

    // MARK: - Group Picker

    @ViewBuilder
    private var groupPicker: some View {
        Picker("Group", selection: groupIDBinding) {
            Text("None").tag(UUID?.none)
            ForEach(store.sortedGroups) { group in
                Text(group.name).tag(UUID?.some(group.id))
            }
        }
    }

    private var groupIDBinding: Binding<UUID?> {
        Binding(
            get: { workflow.groupID },
            set: { workflow.groupID = $0 }
        )
    }

    // MARK: - Trigger Bindings

    private enum TriggerType: Hashable {
        case manual, schedule
    }

    private var triggerTypeBinding: Binding<TriggerType> {
        Binding(
            get: {
                if case .schedule = workflow.trigger { return .schedule }
                return .manual
            },
            set: {
                switch $0 {
                case .manual:
                    workflow.trigger = .manual
                case .schedule:
                    workflow.trigger = .schedule(.hourly())
                }
            }
        )
    }

    // MARK: - Other Bindings

    private var modelBinding: Binding<String> {
        Binding(
            get: { workflow.model ?? "" },
            set: { workflow.model = $0.isEmpty ? nil : $0 }
        )
    }

    private var permissionBinding: Binding<PermissionMode?> {
        Binding(
            get: { workflow.permissionMode ?? .default },
            set: { workflow.permissionMode = $0 }
        )
    }
}
