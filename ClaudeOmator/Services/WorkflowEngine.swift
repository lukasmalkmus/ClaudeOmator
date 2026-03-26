@preconcurrency import Combine
import Foundation
import Observation
import OSLog
import ClaudeCodeSDK
import SwiftAnthropic

@Observable
final class LiveOutputBuffer {
    var text: String = ""
}

@Observable
final class WorkflowEngine {
    private(set) var runningWorkflows: Set<UUID> = []
    private(set) var claudeAvailable: Bool?

    private(set) var liveOutputBuffers: [UUID: LiveOutputBuffer] = [:]
    @ObservationIgnored private var outputBuffers: [UUID: [String]] = [:]
    @ObservationIgnored private var outputLengths: [UUID: Int] = [:]

    private let store: WorkflowStore
    private let activityStore: ActivityStore
    private let notificationService = NotificationService()
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    private var scheduleTasks: [UUID: Task<Void, Never>] = [:]
    private var flushTask: Task<Void, Never>?
    private let maxConcurrent = 3

    private static let logger = Logger(subsystem: "com.lukasmalkmus.ClaudeOmator", category: "engine")

    private static let claudeConfig: ClaudeCodeConfiguration = {
        var config = ClaudeCodeConfiguration.default
        config.additionalPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.npm/bin",
        ] + ClaudeCodeConfiguration.default.additionalPaths

        var env = config.environment
        env["CLAUDECODE"] = ""
        env["CLAUDE_CODE_SESSION"] = ""
        config.environment = env

        return config
    }()

    init(store: WorkflowStore, activityStore: ActivityStore = ActivityStore()) {
        self.store = store
        self.activityStore = activityStore
    }

    nonisolated deinit {
        // @Observable class is MainActor-isolated; deinit runs on the main
        // thread during the last release, so assumeIsolated is safe here.
        MainActor.assumeIsolated {
            for task in runTasks.values { task.cancel() }
            for task in scheduleTasks.values { task.cancel() }
            flushTask?.cancel()
        }
    }

    func validateClaude() {
        Task {
            do {
                let client = try ClaudeCodeClient(configuration: Self.claudeConfig)
                claudeAvailable = try await client.validateCommand("claude")
            } catch {
                claudeAvailable = false
            }
        }
    }

    // MARK: - Execution

    func run(_ workflow: Workflow) {
        guard workflow.isEnabled else { return }
        guard workflow.isConfigured else { return }
        guard !runningWorkflows.contains(workflow.id) else { return }
        guard runningWorkflows.count < maxConcurrent else { return }

        runningWorkflows.insert(workflow.id)
        outputBuffers[workflow.id] = []
        outputLengths[workflow.id] = 0
        liveOutputBuffers[workflow.id] = LiveOutputBuffer()
        updateLastRun(for: workflow.id, status: .running)

        var entry = ActivityEntry(
            workflowID: workflow.id,
            workflowName: workflow.displayName
        )
        activityStore.save(entry)

        let workflowID = workflow.id
        runTasks[workflowID] = Task {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Workflow execution: \(workflow.name)"
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                runningWorkflows.remove(workflowID)
                runTasks.removeValue(forKey: workflowID)
                outputBuffers.removeValue(forKey: workflowID)
                outputLengths.removeValue(forKey: workflowID)
                liveOutputBuffers.removeValue(forKey: workflowID)
            }

            do {
                var config = Self.claudeConfig
                if let dir = workflow.workingDirectory {
                    guard dir.hasPrefix("/") else {
                        updateLastRun(for: workflowID, status: .failed, error: "Working directory must be an absolute path")
                        return
                    }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                        updateLastRun(for: workflowID, status: .failed, error: "Working directory does not exist: \(dir)")
                        return
                    }
                    config.workingDirectory = dir
                }

                let client = try ClaudeCodeClient(configuration: config)

                var options = ClaudeCodeOptions()
                if let model = workflow.model {
                    options.model = model
                }
                if let mode = workflow.permissionMode {
                    switch mode {
                    case .default:
                        options.permissionMode = .default
                    case .plan:
                        options.permissionMode = .plan
                    case .auto:
                        options.permissionMode = .acceptEdits
                    }
                }
                let result = try await client.runSinglePrompt(
                    prompt: workflow.prompt,
                    outputFormat: .streamJson,
                    options: options
                )

                try Task.checkCancellation()

                switch result {
                case .stream(let publisher):
                    var outputText = ""
                    var sessionID: String?
                    for try await chunk in publisher.values {
                        try Task.checkCancellation()
                        switch chunk {
                        case .assistant(let msg):
                            for block in msg.message.content {
                                switch block {
                                case .text(let text, _):
                                    appendOutput(for: workflowID, text: text)
                                case .toolUse(let toolUse):
                                    let detail = Self.toolDetail(name: toolUse.name, input: toolUse.input)
                                    appendOutput(for: workflowID, text: "\n→ \(toolUse.name)\(detail)\n")
                                case .serverToolUse(let serverTool):
                                    appendOutput(for: workflowID, text: "\n→ \(serverTool.name)\n")
                                case .toolResult(let result):
                                    if result.isError == true {
                                        appendOutput(for: workflowID, text: "\n✗ Tool error\n")
                                    }
                                    if case .string(let text) = result.content, !text.isEmpty {
                                        let snippet = text.count > 500 ? String(text.prefix(500)) + "…" : text
                                        appendOutput(for: workflowID, text: snippet + "\n")
                                    }
                                case .codeExecutionToolResult(let codeResult):
                                    appendOutput(for: workflowID, text: "\n⚡ \(codeResult.type.replacingOccurrences(of: "_", with: " "))\n")
                                default:
                                    break
                                }
                            }
                        case .result(let msg):
                            outputText = msg.result ?? ""
                            sessionID = msg.sessionId
                        default:
                            break
                        }
                    }
                    entry.status = .succeeded
                    entry.resultSummary = outputText
                    entry.output = liveOutputBuffers[workflowID]?.text
                    entry.sessionID = sessionID
                    entry.completedAt = Date()
                    activityStore.save(entry)
                    updateLastRun(for: workflowID, status: .succeeded, output: outputText)

                case .json(let msg):
                    let status: RunResult.Status = msg.isError ? .failed : .succeeded
                    entry.status = status
                    entry.resultSummary = msg.result
                    entry.sessionID = msg.sessionId
                    entry.completedAt = Date()
                    activityStore.save(entry)
                    updateLastRun(for: workflowID, status: status, output: msg.result)

                case .text(let text):
                    entry.status = .succeeded
                    entry.resultSummary = text
                    entry.completedAt = Date()
                    activityStore.save(entry)
                    updateLastRun(for: workflowID, status: .succeeded, output: text)
                }
            } catch is CancellationError {
                entry.status = .cancelled
                entry.completedAt = Date()
                activityStore.save(entry)
                updateLastRun(for: workflowID, status: .cancelled)
            } catch {
                Self.logger.error("Workflow execution failed: \(error, privacy: .private)")
                entry.status = .failed
                entry.errorMessage = error.localizedDescription
                entry.output = liveOutputBuffers[workflowID]?.text
                entry.completedAt = Date()
                activityStore.save(entry)
                updateLastRun(for: workflowID, status: .failed, error: error.localizedDescription)
            }
        }
    }

    func cancel(_ id: UUID) {
        runTasks[id]?.cancel()
    }

    func isRunning(_ id: UUID) -> Bool {
        runningWorkflows.contains(id)
    }

    func cancelAll() {
        for task in runTasks.values { task.cancel() }
        for task in scheduleTasks.values { task.cancel() }
    }

    // MARK: - Schedule Management

    func startScheduleLoops() {
        for var workflow in store.workflows {
            if workflow.lastRun?.status == .running {
                workflow.lastRun = RunResult(
                    status: .failed,
                    timestamp: workflow.lastRun?.timestamp ?? Date(),
                    errorMessage: "Interrupted by app termination"
                )
                store.update(workflow)
            }
        }

        for workflow in store.workflows {
            startScheduleIfNeeded(workflow)
        }
    }

    func startScheduleIfNeeded(_ workflow: Workflow) {
        guard workflow.isEnabled,
              case .schedule(let schedule) = workflow.trigger,
              scheduleTasks[workflow.id] == nil else { return }

        let workflowID = workflow.id
        scheduleTasks[workflowID] = Task {
            defer { scheduleTasks.removeValue(forKey: workflowID) }
            let clock = ContinuousClock()
            do {
                while true {
                    let sleepDuration = self.sleepDuration(for: schedule)
                    let tolerance = max(sleepDuration * 0.1, .seconds(10))
                    try await clock.sleep(for: sleepDuration, tolerance: tolerance)
                    guard let current = store.workflows.first(where: { $0.id == workflowID }),
                          current.isEnabled,
                          case .schedule = current.trigger else { break }
                    run(current)
                }
            } catch {
                // CancellationError exits cleanly
            }
        }
    }

    func stopSchedule(_ id: UUID) {
        scheduleTasks[id]?.cancel()
        scheduleTasks.removeValue(forKey: id)
    }

    func nextRunDate(for workflow: Workflow) -> Date? {
        guard case .schedule(let schedule) = workflow.trigger else { return nil }
        let reference = workflow.lastRun?.timestamp ?? Date()
        return schedule.nextFireDate(after: reference)
    }

    private func sleepDuration(for schedule: RecurrenceSchedule) -> Duration {
        guard let nextFire = schedule.nextFireDate() else {
            return .seconds(3600)
        }
        let seconds = max(60, nextFire.timeIntervalSinceNow)
        return .seconds(seconds)
    }

    // MARK: - Tool Detail Extraction

    private static func toolDetail(name: String, input: [String: MessageResponse.Content.DynamicContent]) -> String {
        let value: String? = switch name {
        case "Skill":
            input["skillName"]?.stringValue
        case "Bash":
            input["command"]?.stringValue.map { cmd in
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstLine = trimmed.prefix(while: { $0 != "\n" })
                return String(firstLine.prefix(120))
            }
        case "Read", "Edit", "Write":
            input["file_path"]?.stringValue.map { path in
                (path as NSString).lastPathComponent
            }
        case "Grep":
            input["pattern"]?.stringValue
        case "Glob":
            input["pattern"]?.stringValue
        case "ToolSearch":
            input["query"]?.stringValue
        case "Agent":
            input["description"]?.stringValue
        case "WebFetch":
            input["url"]?.stringValue
        case "WebSearch":
            input["query"]?.stringValue
        default:
            nil
        }

        guard let value, !value.isEmpty else { return "" }
        let truncated = value.count > 200 ? String(value.prefix(200)) + "…" : value
        return ": \(truncated)"
    }

    // MARK: - Output Buffering

    private func appendOutput(for id: UUID, text: String) {
        let currentLength = outputLengths[id, default: 0]
        guard currentLength < 256_000 else { return }
        outputBuffers[id, default: []].append(text)
        outputLengths[id] = currentLength + text.count
        ensureFlushLoop()
    }

    private func ensureFlushLoop() {
        guard flushTask == nil else { return }
        flushTask = Task {
            defer { flushTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                var hasData = false
                for id in outputBuffers.keys {
                    let chunks = outputBuffers[id, default: []]
                    guard !chunks.isEmpty else { continue }
                    liveOutputBuffers[id]?.text.append(contentsOf: chunks.joined())
                    outputBuffers[id] = []
                    hasData = true
                }
                if !hasData && runningWorkflows.isEmpty { break }
            }
        }
    }

    // MARK: - Run Status

    private func updateLastRun(for id: UUID, status: RunResult.Status, output: String? = nil, error: String? = nil) {
        guard var workflow = store.workflows.first(where: { $0.id == id }) else { return }
        workflow.lastRun = RunResult(
            status: status,
            timestamp: Date(),
            outputSnippet: output,
            errorMessage: error
        )
        store.update(workflow)

        if workflow.notifyOnCompletion {
            notificationService.send(for: workflow, status: status, output: output, error: error)
        }
    }
}

extension AnyPublisher where Failure: Error {
    nonisolated var values: AsyncThrowingStream<Output, Error> {
        AsyncThrowingStream { continuation in
            let cancellable = self.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished: continuation.finish()
                    case .failure(let error): continuation.finish(throwing: error)
                    }
                },
                receiveValue: { value in
                    // Combine delivers on the publisher's scheduler; the value
                    // is only forwarded into the AsyncStream, so the send is safe.
                    nonisolated(unsafe) let v = value
                    continuation.yield(v)
                }
            )
            continuation.onTermination = { @Sendable _ in cancellable.cancel() }
        }
    }
}
