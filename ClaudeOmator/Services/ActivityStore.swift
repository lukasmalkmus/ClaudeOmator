import Foundation
import Observation
import OSLog

@Observable
final class ActivityStore {
    private(set) var entries: [ActivityEntry] = []

    private let baseDirectory: URL
    private static let maxEntriesPerWorkflow = 10
    private static let logger = Logger(subsystem: "com.lukasmalkmus.ClaudeOmator", category: "activity")

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory must be available on macOS")
        }
        self.baseDirectory = appSupport
            .appendingPathComponent("com.lukasmalkmus.ClaudeOmator", isDirectory: true)
            .appendingPathComponent("activity", isDirectory: true)
        createDirectoryIfNeeded(baseDirectory, permissions: 0o700)
        Task {
            loadAll()
            cleanupStaleRunning()
        }
    }

    // MARK: - Public API

    func save(_ entry: ActivityEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        writeEntry(entry)
        pruneIfNeeded(workflowID: entry.workflowID)
    }

    func entries(for workflowID: UUID) -> [ActivityEntry] {
        entries
            .filter { $0.workflowID == workflowID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func recentEntries(limit: Int = 20) -> [ActivityEntry] {
        Array(
            entries
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    func entry(id: UUID) -> ActivityEntry? {
        entries.first { $0.id == id }
    }

    func deleteEntries(for workflowID: UUID) {
        entries.removeAll { $0.workflowID == workflowID }
        let dir = workflowDirectory(workflowID)
        try? FileManager.default.removeItem(at: dir)
    }

    private func cleanupStaleRunning() {
        for (index, entry) in entries.enumerated() where entry.status == .running {
            var fixed = entry
            fixed.status = .failed
            fixed.errorMessage = "Interrupted (app terminated unexpectedly)"
            fixed.completedAt = entry.startedAt
            entries[index] = fixed
            writeEntry(fixed)
        }
    }

    // MARK: - Persistence

    private func workflowDirectory(_ workflowID: UUID) -> URL {
        baseDirectory.appendingPathComponent(workflowID.uuidString, isDirectory: true)
    }

    private func entryURL(_ entry: ActivityEntry) -> URL {
        workflowDirectory(entry.workflowID)
            .appendingPathComponent(entry.filename)
    }

    private func outputURL(for entry: ActivityEntry) -> URL {
        workflowDirectory(entry.workflowID)
            .appendingPathComponent("\(entry.id.uuidString)_output.txt")
    }

    func loadOutput(for entryID: UUID) -> String? {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return nil }

        let url = outputURL(for: entry)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        // Migration: read output from legacy JSON entries that stored it inline
        let jsonURL = entryURL(entry)
        guard let data = try? Data(contentsOf: jsonURL) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["output"] as? String
    }

    private func writeEntry(_ entry: ActivityEntry) {
        let dir = workflowDirectory(entry.workflowID)
        createDirectoryIfNeeded(dir)

        let url = entryURL(entry)
        guard let data = try? Self.encoder.encode(entry) else { return }
        let outputText = entry.output
        let outURL = outputURL(for: entry)

        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            if let text = outputText, !text.isEmpty {
                try? text.write(to: outURL, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: outURL.path
                )
            }
        }
    }

    private func loadAll() {
        let fm = FileManager.default
        guard let workflowDirs = try? fm.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for dir in workflowDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: file)
                    let entry = try Self.decoder.decode(ActivityEntry.self, from: data)
                    entries.append(entry)
                } catch {
                    Self.logger.warning("Skipping corrupt activity file \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    private func pruneIfNeeded(workflowID: UUID) {
        let workflowEntries = entries(for: workflowID)
        guard workflowEntries.count > Self.maxEntriesPerWorkflow else { return }

        let toRemove = workflowEntries.suffix(from: Self.maxEntriesPerWorkflow)
        for entry in toRemove {
            entries.removeAll { $0.id == entry.id }
            try? FileManager.default.removeItem(at: entryURL(entry))
            try? FileManager.default.removeItem(at: outputURL(for: entry))
        }
    }

    private func createDirectoryIfNeeded(_ directory: URL, permissions: Int? = nil) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let permissions {
            try? fm.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: directory.path
            )
        }
    }

    // MARK: - Preview Support

    #if DEBUG
    static func preview(entries: [ActivityEntry] = []) -> ActivityStore {
        let store = ActivityStore()
        store.entries = entries
        return store
    }
    #endif
}
