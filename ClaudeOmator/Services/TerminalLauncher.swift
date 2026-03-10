import AppKit
import OSLog

enum TerminalLauncher {
    private static let logger = Logger(
        subsystem: "com.lukasmalkmus.ClaudeOmator",
        category: "terminal"
    )

    static func resumeSession(
        sessionID: String,
        workingDirectory: String?
    ) {
        let command = buildResumeCommand(
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )

        let bundleID = AppSettings.shared.resolvedTerminalBundleID
        switch bundleID {
        case "com.mitchellh.ghostty":
            launchGhostty(command: command)
        default:
            launchTerminalApp(command: command)
        }
    }

    // MARK: - Command Building

    private static func buildResumeCommand(
        sessionID: String,
        workingDirectory: String?
    ) -> String {
        var parts: [String] = ["unset CLAUDECODE"]

        if let dir = workingDirectory {
            parts.append("cd \(shellQuote(dir))")
        }

        parts.append("claude --resume \(shellQuote(sessionID))")
        return parts.joined(separator: " && ")
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Terminal Launchers

    private static func launchGhostty(command: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("claudeomator-\(UUID().uuidString).sh")
        let content = "#!\(shell) -li\n\(command)\nrm -f \(shellQuote(scriptPath.path))\n"
        guard let data = content.data(using: .utf8) else { return }

        do {
            try data.write(to: scriptPath)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: scriptPath.path
            )
        } catch {
            logger.error("Failed to create temp script: \(error, privacy: .private)")
            return
        }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [
            "-na", "Ghostty",
            "--args",
            "--command=\(scriptPath.path)",
            "--quit-after-last-window-closed=true",
        ]
        do {
            try process.run()
        } catch {
            logger.error("Failed to launch Ghostty: \(error, privacy: .private)")
            try? FileManager.default.removeItem(at: scriptPath)
        }
    }

    private static func launchTerminalApp(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """
        runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript error: \(error, privacy: .private)")
        }
    }
}
