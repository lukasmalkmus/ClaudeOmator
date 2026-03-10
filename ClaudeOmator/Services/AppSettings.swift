import AppKit
import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var terminalBundleID: String {
        didSet { UserDefaults.standard.set(terminalBundleID, forKey: "terminalBundleID") }
    }

    var resolvedTerminalBundleID: String {
        if !terminalBundleID.isEmpty { return terminalBundleID }
        return Self.detectTerminal()
    }

    static let knownTerminals: [(name: String, bundleID: String)] = [
        ("Terminal", "com.apple.Terminal"),
        ("Ghostty", "com.mitchellh.ghostty"),
    ]

    private init() {
        self.terminalBundleID = UserDefaults.standard.string(forKey: "terminalBundleID") ?? ""
    }

    private static func detectTerminal() -> String {
        let running = NSWorkspace.shared.runningApplications
        for terminal in knownTerminals {
            if running.contains(where: { $0.bundleIdentifier == terminal.bundleID }) {
                return terminal.bundleID
            }
        }
        return "com.apple.Terminal"
    }
}
