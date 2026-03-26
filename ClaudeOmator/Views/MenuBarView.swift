import SwiftUI

struct MenuBarView: View {
    let store: WorkflowStore
    let activityStore: ActivityStore
    let engine: WorkflowEngine
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ClaudeOmator") {
            appDelegate.openMainWindow()
        }
        .keyboardShortcut("o", modifiers: .command)
        .onAppear {
            appDelegate.openWindowAction = openWindow
        }

        Divider()

        if engine.claudeAvailable == false {
            Label("Claude CLI not found", systemImage: "exclamationmark.triangle")
                .disabled(true)
            Divider()
        }

        if store.workflows.isEmpty {
            Text("No workflows configured")
                .disabled(true)
        } else {
            ForEach(store.groupedWorkflows, id: \.0?.id) { group, workflows in
                if let group {
                    Section(group.name) {
                        ForEach(workflows) { workflow in
                            workflowButton(for: workflow)
                        }
                    }
                } else {
                    ForEach(workflows) { workflow in
                        workflowButton(for: workflow)
                    }
                }
            }
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit ClaudeOmator") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func workflowButton(for workflow: Workflow) -> some View {
        Button {
            if engine.isRunning(workflow.id) {
                engine.cancel(workflow.id)
            } else {
                engine.run(workflow)
            }
        } label: {
            Label {
                Text(workflowLabel(for: workflow))
            } icon: {
                Image(systemName: statusIcon(for: workflow))
            }
        }
        .disabled(!workflow.isEnabled || engine.claudeAvailable != true)
    }

    private func statusIcon(for workflow: Workflow) -> String {
        if engine.isRunning(workflow.id) {
            return "stop.circle.fill"
        }
        if let lastRun = workflow.lastRun {
            return lastRun.status.systemImage
        }
        if workflow.isEnabled, case .schedule = workflow.trigger {
            return "clock"
        }
        return "circle"
    }

    private func workflowLabel(for workflow: Workflow) -> String {
        let name = workflow.displayName
        if engine.isRunning(workflow.id) {
            return "\(name) (running)"
        }
        if let lastRun = workflow.lastRun {
            switch lastRun.status {
            case .failed:
                return "\(name) (failed)"
            case .cancelled:
                return "\(name) (cancelled)"
            default:
                break
            }
        }
        if let nextRun = engine.nextRunDate(for: workflow) {
            let remaining = nextRun.timeIntervalSinceNow
            if remaining > 0 {
                return "\(name) (in \(formatInterval(remaining)))"
            }
        }
        return name
    }

    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "\(minutes)m"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d"
        }
    }
}

#if DEBUG
#Preview("Menu Bar") {
    let store = WorkflowStore.preview(
        workflows: [
            Workflow(name: "Daily Brief", isEnabled: true, prompt: "Summarize"),
            Workflow(name: "Code Review", isEnabled: true, prompt: "Review"),
        ]
    )
    let activityStore = ActivityStore()
    let engine = WorkflowEngine(store: store, activityStore: activityStore)

    MenuBarView(store: store, activityStore: activityStore, engine: engine, appDelegate: AppDelegate())
        .frame(width: 250)
}
#endif
