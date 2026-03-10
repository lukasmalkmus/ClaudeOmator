import SwiftUI
import Textual

struct WorkflowOutputView: View {
    let entry: ActivityEntry?
    let workflow: Workflow?
    let liveOutput: LiveOutputBuffer?
    let isRunning: Bool
    let onCancel: () -> Void
    var loadOutput: ((UUID) -> String?)? = nil

    private enum RenderMode: String, CaseIterable, Identifiable {
        case rendered = "Rendered"
        case raw = "Raw"

        var id: Self { self }

        var systemImageName: String {
            switch self {
            case .rendered: "doc.richtext"
            case .raw: "doc.plaintext"
            }
        }
    }

    @State private var renderMode: RenderMode = .rendered
    @State private var showFullOutput = false
    @State private var showCopied = false
    @State private var styledCache = AttributedString()
    @State private var styledLength = 0
    @State private var lazyOutput: String?

    var body: some View {
        let showLive = isRunning && (entry == nil || entry?.status == .running)

        VStack(alignment: .leading, spacing: 0) {
            let name = entry?.workflowName ?? workflow?.displayName ?? "Unknown"
            let status = entry?.status ?? workflow?.lastRun?.status

            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                if showLive {
                    ProgressView()
                        .controlSize(.small)
                    Button("Stop") { onCancel() }
                } else if let status {
                    Label(status.label, systemImage: status.systemImage)
                        .foregroundStyle(status.color)
                    if let duration = entry?.formattedDuration {
                        Text("(\(duration))")
                            .foregroundStyle(.secondary)
                    }
                    if let time = entry?.completedAt ?? entry?.startedAt {
                        Text(time, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showLive, liveOutput?.text.isEmpty == false, !styledCache.characters.isEmpty {
                        Text(styledCache)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if showLive {
                        Text("Waiting for output…")
                            .foregroundStyle(.secondary)
                    } else if let entry {
                        if let summary = entry.resultSummary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Result")
                                    .sectionLabelStyle()
                                markdownText(summary, mode: renderMode)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        DisclosureGroup(isExpanded: $showFullOutput) {
                            if let output = lazyOutput, !output.isEmpty {
                                Text(output)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("No full output available")
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Text("Full Output")
                                .sectionLabelStyle()
                        }
                        .onChange(of: showFullOutput) {
                            if showFullOutput, lazyOutput == nil {
                                lazyOutput = loadOutput?(entry.id)
                            }
                        }

                        if let error = entry.errorMessage {
                            Text("Error: \(error)")
                                .font(.body.monospaced())
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if entry.resultSummary == nil && entry.errorMessage == nil {
                            Text("No output")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No output")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
        }
        .onChange(of: liveOutput?.text) { oldValue, newValue in
            guard let text = newValue, text.count > styledLength else {
                if newValue == nil || (oldValue?.count ?? 0) > (newValue?.count ?? 0) {
                    styledCache = AttributedString()
                    styledLength = 0
                }
                return
            }
            let newPart = String(text.dropFirst(styledLength))
            styledCache.append(Self.styleLines(newPart))
            styledLength = text.count
        }
        .toolbar {
            if let entry, !showLive {
                if entry.resultSummary != nil {
                    ToolbarItem {
                        Picker("Render Mode", selection: $renderMode) {
                            ForEach(RenderMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.systemImageName)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Switch between rich rendering and raw text")
                    }
                }

                ToolbarItem {
                    Button {
                        if let text = entry.resultSummary, !text.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            showCopied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showCopied = false
                            }
                        }
                    } label: {
                        Label(
                            showCopied ? "Copied!" : "Copy Result",
                            systemImage: showCopied ? "checkmark" : "doc.on.doc"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(entry.resultSummary?.isEmpty != false)
                    .help("Copy the final result to the clipboard")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard let sessionID = entry.sessionID else { return }
                        TerminalLauncher.resumeSession(
                            sessionID: sessionID,
                            workingDirectory: workflow?.workingDirectory
                        )
                    } label: {
                        Label("Resume in Claude Code", systemImage: "terminal")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(entry.sessionID == nil)
                    .help("Resume this session in Claude Code")
                }
            }
        }
    }

    // MARK: - Markdown Rendering

    private static let maxMarkdownLength = 50_000

    @ViewBuilder
    private func markdownText(_ text: String, mode: RenderMode) -> some View {
        switch mode {
        case .rendered:
            if text.count <= Self.maxMarkdownLength {
                StructuredText(markdown: text)
                    .textual.structuredTextStyle(.gitHub)
            } else {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        case .raw:
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Styled Live Output

    static func styleLines(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            let str = String(line)
            var attributed = AttributedString(str)

            if str.hasPrefix("→ ") {
                attributed.foregroundColor = .secondary
                attributed.font = .body.monospaced().bold()
            } else if str.hasPrefix("✗ ") {
                attributed.foregroundColor = .red
            } else if str.hasPrefix("⚡ ") {
                attributed.foregroundColor = .purple
            }

            result.append(attributed)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }
}
