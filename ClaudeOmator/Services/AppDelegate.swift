import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var navigationState: NavigationState?
    var activityStore: ActivityStore?
    var openWindowAction: OpenWindowAction?

    var engine: WorkflowEngine?

    static let notificationCategoryID = "WORKFLOW_RESULT"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else { return }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View",
            options: .foreground
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Window & Dock Icon

    func openMainWindow() {
        openWindowAction?(id: "main")
        showDockIcon()
    }

    func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Quit Confirmation

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine, !engine.runningWorkflows.isEmpty else {
            return .terminateNow
        }

        let count = engine.runningWorkflows.count
        let alert = NSAlert()
        alert.messageText = "Quit ClaudeOmator?"
        alert.informativeText = "\(count) workflow\(count == 1 ? " is" : "s are") still running. Quitting will cancel \(count == 1 ? "it" : "them")."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Closes all non-menubar windows and hides to the menubar.
    func closeWindowsAndHide() {
        for window in NSApp.windows where window.isVisible {
            if window.className.contains("StatusBar") || window.title == "Item-0" {
                continue
            }
            window.close()
        }
        hideDockIcon()
    }

    // MARK: - Single Instance

    /// If another instance is already running, activate it and terminate self.
    /// Returns true if this is the sole instance and startup should continue.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }

        guard let existing = others.first else { return true }

        if !existing.activate() {
            if let url = existing.bundleURL {
                NSWorkspace.shared.open(url)
            }
        }

        Task { @MainActor in
            NSApp.terminate(nil)
        }
        return false
    }

    // MARK: - Notifications

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let idString = response.notification.request.content.userInfo["workflowID"] as? String,
              let id = UUID(uuidString: idString) else { return }

        if response.actionIdentifier == "DISMISS" { return }

        await MainActor.run {
            guard let runID = activityStore?.entries(for: id).first?.id else { return }
            navigationState?.selection = .activity(workflowID: id, runID: runID)
            openMainWindow()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list, .banner, .sound]
    }
}
