import SwiftUI

struct MainView: View {
    var store: WorkflowStore
    let activityStore: ActivityStore
    let engine: WorkflowEngine

    @Environment(NavigationState.self) private var navigationState

    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var targetWorkflowID: UUID?
    @State private var editingGroup: WorkflowGroup?
    @State private var dropTargetID: UUID?
    @State private var workflowToDelete: Workflow?
    @State private var groupToDelete: WorkflowGroup?

    var body: some View {
        @Bindable var nav = navigationState
        NavigationSplitView {
            List(selection: $nav.selection) {
                workflowsSection
                activitySection
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Workflow") {
                            let workflow = Workflow(name: "New Workflow")
                            store.add(workflow)
                            navigationState.selection = .workflow(workflow.id)
                        }
                        Button("New Group...") {
                            targetWorkflowID = nil
                            newGroupName = ""
                            showingNewGroupAlert = true
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        } detail: {
            NavigationStack(path: $nav.detailPath) {
                detailView
                    .navigationDestination(for: NavigationState.ActivityDestination.self) { dest in
                        if let entry = activityStore.entry(id: dest.runID) {
                            WorkflowOutputView(
                                entry: entry,
                                workflow: store.workflows.first { $0.id == dest.workflowID },
                                liveOutput: engine.liveOutputBuffers[dest.workflowID],
                                isRunning: engine.isRunning(dest.workflowID),
                                onCancel: { engine.cancel(dest.workflowID) },
                                loadOutput: { activityStore.loadOutput(for: $0) }
                            )
                        } else {
                            ContentUnavailableView(
                                "Run Not Found",
                                systemImage: "questionmark.folder",
                                description: Text("This activity entry may have been deleted.")
                            )
                        }
                    }
            }
        }
        .navigationTitle("ClaudeOmator")
        .onChange(of: nav.selection) {
            nav.detailPath = NavigationPath()
        }
        .alert("New Group", isPresented: $showingNewGroupAlert) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) {
                newGroupName = ""
                targetWorkflowID = nil
            }
            Button("Create") {
                if !newGroupName.isEmpty {
                    let group = WorkflowGroup(name: newGroupName)
                    store.addGroup(group)
                    if let wfID = targetWorkflowID,
                       var wf = store.workflows.first(where: { $0.id == wfID }) {
                        wf.groupID = group.id
                        store.update(wf)
                    }
                }
                newGroupName = ""
                targetWorkflowID = nil
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(group: group, store: store) {
                editingGroup = nil
            }
        }
        .confirmationDialog(
            "Delete \(workflowToDelete?.displayName ?? "workflow")?",
            isPresented: Binding(
                get: { workflowToDelete != nil },
                set: { if !$0 { workflowToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let workflow = workflowToDelete {
                    if case .workflow(workflow.id) = navigationState.selection {
                        navigationState.selection = nil
                    }
                    engine.stopSchedule(workflow.id)
                    activityStore.deleteEntries(for: workflow.id)
                    store.delete(workflow)
                }
            }
        } message: {
            Text("This will also delete all activity history for this workflow. This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete group \"\(groupToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let group = groupToDelete {
                    store.deleteGroup(group.id)
                }
            }
        } message: {
            Text("Workflows in this group will be ungrouped. This action cannot be undone.")
        }
    }

    // MARK: - Sidebar Sections

    @ViewBuilder
    private var workflowsSection: some View {
        Section("Workflows") {
            ForEach(store.groupedWorkflows, id: \.0?.id) { group, workflows in
                if let group {
                    groupHeader(group)
                    workflowRows(workflows, indented: true)
                } else {
                    workflowRows(workflows, indented: false)
                }
            }
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: WorkflowGroup) -> some View {
        Text(group.name)
            .sectionLabelStyle()
            .padding(.leading, 4)
            .padding(.top, 8)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Edit Group...") {
                editingGroup = group
            }
            Button("Delete Group", role: .destructive) {
                groupToDelete = group
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            store.moveWorkflow(id: id, toGroupID: group.id)
            return true
        }
    }

    @ViewBuilder
    private func workflowRows(_ workflows: [Workflow], indented: Bool) -> some View {
        ForEach(workflows) { workflow in
            NavigationLink(value: SidebarSelection.workflow(workflow.id)) {
                HStack {
                    if engine.isRunning(workflow.id) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Running")
                    } else if !workflow.isConfigured {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Not configured")
                    } else {
                        Image(systemName: workflow.isEnabled ? "bolt.fill" : "bolt.slash")
                            .foregroundStyle(workflow.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .accessibilityLabel(workflow.isEnabled ? "Enabled" : "Disabled")
                    }
                    Text(workflow.displayName)
                }
                .padding(.leading, indented ? 12 : 0)
            }
            .draggable(workflow.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first, let id = UUID(uuidString: idString), id != workflow.id else { return false }
                store.moveWorkflow(id: id, toGroupID: workflow.groupID)
                store.moveWorkflow(id: id, before: workflow.id)
                return true
            } isTargeted: { targeted in
                dropTargetID = targeted ? workflow.id : (dropTargetID == workflow.id ? nil : dropTargetID)
            }
            .overlay(alignment: .top) {
                if dropTargetID == workflow.id {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.leading, indented ? 12 : 0)
                }
            }
            .contextMenu {
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
                    .disabled(!workflow.isEnabled || engine.claudeAvailable != true)
                }
                Divider()
                groupMenu(for: workflow)
                Divider()
                Button(workflow.isEnabled ? "Disable" : "Enable") {
                    var updated = workflow
                    updated.isEnabled.toggle()
                    store.update(updated)
                    if !updated.isEnabled {
                        engine.stopSchedule(updated.id)
                    } else {
                        engine.startScheduleIfNeeded(updated)
                    }
                }
                Button("Delete", role: .destructive) {
                    workflowToDelete = workflow
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    workflowToDelete = workflow
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func groupMenu(for workflow: Workflow) -> some View {
        Menu("Move to Group") {
            Button("None") {
                store.moveWorkflow(id: workflow.id, toGroupID: nil)
            }
            .disabled(workflow.groupID == nil)
            if !store.groups.isEmpty {
                Divider()
                ForEach(store.sortedGroups) { group in
                    Button {
                        store.moveWorkflow(id: workflow.id, toGroupID: group.id)
                    } label: {
                        Text(group.name)
                    }
                    .disabled(workflow.groupID == group.id)
                }
            }
            Divider()
            Button("New Group...") {
                targetWorkflowID = workflow.id
                newGroupName = ""
                showingNewGroupAlert = true
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section("Activity") {
            let runningEntries = activityStore.entries
                .filter { $0.status == .running }
                .sorted { $0.startedAt > $1.startedAt }
            let recent = activityStore.recentEntries(limit: 20)
                .filter { entry in entry.status != .running }

            if !runningEntries.isEmpty {
                ForEach(runningEntries) { entry in
                    NavigationLink(value: SidebarSelection.activity(
                        workflowID: entry.workflowID,
                        runID: entry.id
                    )) {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(entry.workflowName)
                        }
                    }
                }
            }

            ForEach(recent) { entry in
                NavigationLink(value: SidebarSelection.activity(
                    workflowID: entry.workflowID,
                    runID: entry.id
                )) {
                    HStack {
                        Image(systemName: entry.status.systemImage)
                            .foregroundStyle(entry.status.color)
                            .accessibilityLabel(entry.status.label)
                        VStack(alignment: .leading) {
                            Text(entry.workflowName)
                            Text(entry.completedAt ?? entry.startedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if runningEntries.isEmpty && recent.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.selection {
        case .workflow(let id):
            if store.workflows.contains(where: { $0.id == id }) {
                WorkflowEditorView(
                    workflow: Binding(
                        get: {
                            store.workflows.first(where: { $0.id == id }) ?? Workflow(id: id)
                        },
                        set: { updated in
                            let old = store.workflows.first(where: { $0.id == id })
                            store.update(updated)
                            if old?.trigger != updated.trigger || old?.isEnabled != updated.isEnabled {
                                engine.stopSchedule(updated.id)
                                engine.startScheduleIfNeeded(updated)
                            }
                        }
                    ),
                    engine: engine,
                    store: store,
                    activityStore: activityStore
                )
                .id(id)
            } else {
                ContentUnavailableView("Workflow Not Found", systemImage: "questionmark.square.dashed")
            }
        case .activity(let workflowID, let runID):
            WorkflowOutputView(
                entry: activityStore.entry(id: runID),
                workflow: store.workflows.first { $0.id == workflowID },
                liveOutput: engine.liveOutputBuffers[workflowID],
                isRunning: engine.isRunning(workflowID),
                onCancel: { engine.cancel(workflowID) },
                loadOutput: { activityStore.loadOutput(for: $0) }
            )
        case nil:
            ContentUnavailableView("No Selection", systemImage: "sidebar.left")
        }
    }
}

// MARK: - Section Label Style

extension View {
    func sectionLabelStyle() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Previews

#if DEBUG
private func makePreviewData() -> (WorkflowStore, ActivityStore, [WorkflowGroup]) {
    let group = WorkflowGroup(name: "Axiom", icon: "folder.fill", color: .blue)
    var wf1 = Workflow(
        name: "Daily Brief",
        isEnabled: true,
        trigger: .schedule(.daily(hour: 9, minute: 0)),
        prompt: "Summarize today's activity",
        groupID: group.id
    )
    wf1.lastRun = RunResult(status: .succeeded, timestamp: Date().addingTimeInterval(-39600))

    let wf2 = Workflow(
        name: "Weekly Brief",
        isEnabled: true,
        trigger: .schedule(.weekly(weekdays: [.monday], hour: 9, minute: 0)),
        prompt: "Summarize the week",
        groupID: group.id
    )
    let wf3 = Workflow(
        name: "Code Review",
        isEnabled: false,
        trigger: .schedule(.monthlyMatching(ordinal: -2, hour: 10, minute: 0)),
        prompt: "Review open PRs"
    )

    let store = WorkflowStore.preview(
        workflows: [wf1, wf2, wf3],
        groups: [group]
    )

    var entry1 = ActivityEntry(
        workflowID: wf1.id,
        workflowName: "Daily Brief",
        startedAt: Date().addingTimeInterval(-39700),
        status: .succeeded
    )
    entry1.completedAt = Date().addingTimeInterval(-39600)
    entry1.resultSummary = "All systems operational. No incidents reported."

    var entry2 = ActivityEntry(
        workflowID: wf1.id,
        workflowName: "Daily Brief",
        startedAt: Date().addingTimeInterval(-126000),
        status: .failed
    )
    entry2.completedAt = Date().addingTimeInterval(-125900)
    entry2.errorMessage = "Claude CLI not found"

    let activityStore = ActivityStore.preview(entries: [entry1, entry2])

    return (store, activityStore, [group])
}

#Preview("Main Window") {
    let (store, activityStore, _) = makePreviewData()
    let engine = WorkflowEngine(store: store, activityStore: activityStore)
    MainView(store: store, activityStore: activityStore, engine: engine)
        .environment(NavigationState())
        .frame(width: 750, height: 500)
}

#Preview("Empty State") {
    let store = WorkflowStore.preview()
    let activityStore = ActivityStore.preview()
    let engine = WorkflowEngine(store: store, activityStore: activityStore)
    MainView(store: store, activityStore: activityStore, engine: engine)
        .environment(NavigationState())
        .frame(width: 750, height: 500)
}
#endif
