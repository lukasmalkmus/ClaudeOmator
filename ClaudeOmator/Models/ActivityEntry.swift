import Foundation

struct ActivityEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let workflowID: UUID
    let workflowName: String
    let startedAt: Date
    var completedAt: Date?
    var status: RunResult.Status
    /// Full output text. Not persisted in JSON; stored in a separate sidecar file
    /// and loaded on demand via `ActivityStore.loadOutput(for:)`.
    var output: String?
    var resultSummary: String?
    var errorMessage: String?
    var sessionID: String?

    private enum CodingKeys: String, CodingKey {
        case id, workflowID, workflowName, startedAt, completedAt
        case status, output, resultSummary, errorMessage, sessionID
    }

    init(
        id: UUID = UUID(),
        workflowID: UUID,
        workflowName: String,
        startedAt: Date = Date(),
        status: RunResult.Status = .running
    ) {
        self.id = id
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.startedAt = startedAt
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workflowID = try container.decode(UUID.self, forKey: .workflowID)
        workflowName = try container.decode(String.self, forKey: .workflowName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decode(RunResult.Status.self, forKey: .status)
        output = nil
        resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workflowID, forKey: .workflowID)
        try container.encode(workflowName, forKey: .workflowName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(resultSummary, forKey: .resultSummary)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
    }

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s"
        } else {
            return "\(Int(duration / 3600))h \(Int((duration / 60).truncatingRemainder(dividingBy: 60)))m"
        }
    }

    private static let filenameFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var filename: String {
        let timestamp = Self.filenameFormatter.string(from: startedAt)
            .replacingOccurrences(of: ":", with: "")
        return "\(timestamp)_\(id.uuidString).json"
    }
}
