import Foundation
import Observation
import OSLog
import SwiftUI

@Observable
final class WorkflowStore {
    private(set) var workflows: [Workflow] = []
    private(set) var groups: [WorkflowGroup] = []

    var sortedGroups: [WorkflowGroup] {
        groups.sorted { $0.name < $1.name }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.lukasmalkmus.ClaudeOmator", category: "store")

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory must be available on macOS")
        }
        let directory = appSupport.appendingPathComponent("com.lukasmalkmus.ClaudeOmator", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("workflows.json")

        createDirectoryIfNeeded(directory)
        load()
    }

    // MARK: - Workflow CRUD

    func add(_ workflow: Workflow) {
        workflows.append(workflow)
        scheduleSave()
    }

    func update(_ workflow: Workflow) {
        guard let index = workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        workflows[index] = workflow
        scheduleSave()
    }

    func delete(_ workflow: Workflow) {
        workflows.removeAll { $0.id == workflow.id }
        scheduleSave()
    }

    func moveWorkflow(id: UUID, toGroupID: UUID?) {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else { return }
        workflows[index].groupID = toGroupID
        scheduleSave()
    }

    func moveWorkflow(id: UUID, before targetID: UUID) {
        guard let sourceIndex = workflows.firstIndex(where: { $0.id == id }),
              let targetIndex = workflows.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else { return }
        let workflow = workflows.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        workflows.insert(workflow, at: insertIndex)
        scheduleSave()
    }

    // MARK: - Group CRUD

    func group(for id: UUID?) -> WorkflowGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    func addGroup(_ group: WorkflowGroup) {
        groups.append(group)
        scheduleSave()
    }

    func updateGroup(_ group: WorkflowGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
        scheduleSave()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        for i in workflows.indices where workflows[i].groupID == id {
            workflows[i].groupID = nil
        }
        scheduleSave()
    }

    // MARK: - Grouped View

    var groupedWorkflows: [(WorkflowGroup?, [Workflow])] {
        let ungrouped = workflows.filter { $0.groupID == nil }
        let grouped = sortedGroups.compactMap { group -> (WorkflowGroup, [Workflow])? in
            let members = workflows.filter { $0.groupID == group.id }
            guard !members.isEmpty else { return nil }
            return (group, members)
        }

        var result: [(WorkflowGroup?, [Workflow])] = []
        if !ungrouped.isEmpty {
            result.append((nil, ungrouped))
        }
        result += grouped.map { ($0.0, $0.1) }
        return result
    }

    // MARK: - Persistence

    private(set) var failedWorkflowNames: [String] = []

    var showLoadWarning: Bool {
        !failedWorkflowNames.isEmpty
    }

    private var canSave: Bool {
        !workflows.isEmpty || failedWorkflowNames.isEmpty
    }

    private struct StorageContainer: Codable {
        var version: Int = 2
        var workflows: [Workflow]
        var groups: [WorkflowGroup]
    }

    private struct ResilientWorkflow: Decodable {
        let workflow: Workflow?

        init(from decoder: Decoder) throws {
            workflow = try? Workflow(from: decoder)
        }
    }

    private struct ResilientContainer: Decodable {
        var version: Int = 2
        var workflows: [ResilientWorkflow]
        var groups: [WorkflowGroup]
    }

    private struct WorkflowNameOnly: Decodable {
        let id: UUID
        let name: String
    }

    private struct NameOnlyContainer: Decodable {
        var workflows: [WorkflowNameOnly]
    }

    private func load() {
        let backupURL = fileURL.appendingPathExtension("bak")

        if let data = readNoFollow(fileURL) {
            if let result = decodeResilient(data) {
                workflows = result.workflows
                groups = result.groups
                failedWorkflowNames = result.failedNames
                let failedCount = result.failedNames.count
                if failedCount > 0 {
                    Self.logger.warning("Failed to decode \(failedCount) workflow(s)")
                }
                return
            }
        }

        if let backupData = readNoFollow(backupURL) {
            if let result = decodeResilient(backupData) {
                workflows = result.workflows
                groups = result.groups
                failedWorkflowNames = result.failedNames
                let failedCount = result.failedNames.count
                Self.logger.warning("Restored from backup (\(failedCount) failed)")
                return
            }
        }
    }

    private func decodeResilient(_ data: Data) -> (workflows: [Workflow], groups: [WorkflowGroup], failedNames: [String])? {
        guard let resilient = try? JSONDecoder().decode(ResilientContainer.self, from: data) else {
            return nil
        }

        let decoded = resilient.workflows.compactMap(\.workflow)
        let decodedIDs = Set(decoded.map(\.id))

        var failedNames: [String] = []
        if decoded.count < resilient.workflows.count {
            let allNames = try? JSONDecoder().decode(NameOnlyContainer.self, from: data)
            failedNames = allNames?.workflows
                .filter { !decodedIDs.contains($0.id) }
                .map(\.name) ?? []
        }

        return (decoded, resilient.groups, failedNames)
    }

    func saveNow() {
        guard canSave else { return }
        saveTask?.cancel()
        save()
    }

    private func save() {
        let container = StorageContainer(workflows: workflows, groups: groups)
        let url = fileURL
        let backupURL = url.appendingPathExtension("bak")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        let data: Data
        do {
            data = try encoder.encode(container)
        } catch {
            Self.logger.error("Failed to encode workflows: \(error, privacy: .private)")
            return
        }

        let logger = Self.logger
        Task.detached(priority: .utility) {
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    try? fm.removeItem(at: backupURL)
                    try? fm.copyItem(at: url, to: backupURL)
                }
                try writeNoFollow(url, data: data)
            } catch {
                logger.error("Failed to write workflows: \(error, privacy: .private)")
            }
        }
    }

    private func scheduleSave() {
        guard canSave else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func createDirectoryIfNeeded(_ directory: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }

        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            Self.logger.error("Failed to create storage directory: \(error, privacy: .private)")
        }
    }

    private func readNoFollow(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return handle.readDataToEndOfFile()
    }

    // MARK: - Preview Support

    #if DEBUG
    static func preview(
        workflows: [Workflow] = [],
        groups: [WorkflowGroup] = []
    ) -> WorkflowStore {
        let store = WorkflowStore()
        store.workflows = workflows
        store.groups = groups
        return store
    }
    #endif
}

nonisolated private func writeNoFollow(_ url: URL, data: Data) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else {
        throw CocoaError(.fileWriteNoPermission)
    }
    defer { close(fd) }

    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
    handle.write(data)
}
