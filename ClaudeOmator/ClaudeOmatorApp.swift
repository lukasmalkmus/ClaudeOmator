import SwiftUI

@main
struct ClaudeOmatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var store: WorkflowStore
    @State private var activityStore: ActivityStore
    @State private var engine: WorkflowEngine
    @State private var navigationState: NavigationState

    var body: some Scene {
        MenuBarExtra("ClaudeOmator", systemImage: "bolt.badge.automatic.fill") {
            MenuBarView(store: store, activityStore: activityStore, engine: engine, appDelegate: appDelegate)
        }

        Settings {
            SettingsView()
        }

        Window("ClaudeOmator", id: "main") {
            MainView(store: store, activityStore: activityStore, engine: engine)
                .onAppear {
                    appDelegate.showDockIcon()
                }
                .onDisappear {
                    appDelegate.hideDockIcon()
                }
        }
        .environment(navigationState)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 900, height: 550)
    }

    init() {
        let s = WorkflowStore()
        _store = State(initialValue: s)
        let a = ActivityStore()
        _activityStore = State(initialValue: a)
        let e = WorkflowEngine(store: s, activityStore: a)
        _engine = State(initialValue: e)
        let nav = NavigationState()
        _navigationState = State(initialValue: nav)
        e.validateClaude()
        e.startScheduleLoops()
        appDelegate.navigationState = nav
        appDelegate.activityStore = a
        appDelegate.engine = e

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // queue: .main guarantees MainActor isolation. Task { @MainActor in }
            // would be async and may not complete before termination.
            MainActor.assumeIsolated {
                s.saveNow()
            }
        }
    }
}
