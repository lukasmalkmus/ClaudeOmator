import Foundation
import FoundationModels
import UserNotifications

final class NotificationService {
    private var hasRequestedPermission = false

    private func ensurePermission() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(for workflow: Workflow, status: RunResult.Status, output: String?, error: String?) {
        guard status != .running else { return }

        ensurePermission()

        Task {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.userInfo = ["workflowID": workflow.id.uuidString]
            content.categoryIdentifier = AppDelegate.notificationCategoryID

            let name = workflow.displayName
            switch status {
            case .succeeded:
                content.title = "\(name) completed"
                if let output, !output.isEmpty {
                    content.body = await summarize(output) ?? "Workflow finished successfully."
                } else {
                    content.body = "Workflow finished successfully."
                }
            case .failed:
                content.title = "\(name) failed"
                content.body = error ?? "An unknown error occurred."
            case .cancelled:
                content.title = "\(name) cancelled"
                content.body = "Workflow was cancelled."
            case .running:
                return
            }

            let request = UNNotificationRequest(
                identifier: "workflow-\(workflow.id)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func summarize(_ text: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let input = String(text.prefix(4000))
        do {
            let session = LanguageModelSession(instructions: "Summarize the following workflow result in 1-2 sentences. Be concise.")
            let response = try await session.respond(to: input)
            let summary = response.content
            return summary.isEmpty ? nil : summary
        } catch {
            return nil
        }
    }
}
