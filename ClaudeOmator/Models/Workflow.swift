import Foundation
import SwiftUI

struct Workflow: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: TriggerConfig
    var prompt: String
    var workingDirectory: String?
    var model: String?
    var permissionMode: PermissionMode?
    var notifyOnCompletion: Bool
    var groupID: UUID?
    var lastRun: RunResult?

    var displayName: String { name.isEmpty ? "Untitled" : name }

    var isConfigured: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && workingDirectory.map({ !$0.isEmpty }) ?? false
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        trigger: TriggerConfig = .manual,
        prompt: String = "",
        workingDirectory: String? = nil,
        model: String? = nil,
        permissionMode: PermissionMode? = nil,
        notifyOnCompletion: Bool = true,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.model = model
        self.permissionMode = permissionMode
        self.notifyOnCompletion = notifyOnCompletion
        self.groupID = groupID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        trigger = try container.decode(TriggerConfig.self, forKey: .trigger)
        prompt = try container.decode(String.self, forKey: .prompt)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode)
        notifyOnCompletion = try container.decodeIfPresent(Bool.self, forKey: .notifyOnCompletion) ?? true
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        lastRun = try container.decodeIfPresent(RunResult.self, forKey: .lastRun)
    }
}

// MARK: - Permission Mode

enum PermissionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case `default`
    case plan
    case auto
    case bypassAll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: "Default"
        case .plan: "Plan"
        case .auto: "Auto (Accept Edits)"
        case .bypassAll: "Bypass All"
        }
    }
}

// MARK: - Trigger Configuration

enum TriggerConfig: Codable, Sendable, Hashable {
    case manual
    case schedule(RecurrenceSchedule)

    private enum CodingKeys: String, CodingKey {
        case type, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "schedule":
            let config = try container.decode(RecurrenceSchedule.self, forKey: .schedule)
            self = .schedule(config)
        default:
            self = .manual
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try container.encode("manual", forKey: .type)
        case .schedule(let config):
            try container.encode("schedule", forKey: .type)
            try container.encode(config, forKey: .schedule)
        }
    }
}

// MARK: - Run Result

struct RunResult: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case succeeded
        case failed
        case cancelled

        var systemImage: String {
            switch self {
            case .running:   "circle.fill"
            case .succeeded: "checkmark.circle.fill"
            case .failed:    "xmark.circle.fill"
            case .cancelled: "minus.circle.fill"
            }
        }

        var label: String {
            rawValue.capitalized
        }

        var color: Color {
            switch self {
            case .running:   .orange
            case .succeeded: .green
            case .failed:    .red
            case .cancelled: .gray
            }
        }
    }

    var status: Status
    var timestamp: Date
    var outputSnippet: String?
    var errorMessage: String?
}

