import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Terminal Handoff") {
                Picker("Terminal App", selection: $settings.terminalBundleID) {
                    Text("Auto-detect").tag("")
                    ForEach(AppSettings.knownTerminals, id: \.bundleID) { terminal in
                        Label {
                            Text(terminal.name)
                        } icon: {
                            TerminalIcon(bundleID: terminal.bundleID)
                        }
                        .tag(terminal.bundleID)
                    }
                }

                if settings.terminalBundleID.isEmpty {
                    let detected = AppSettings.knownTerminals.first { $0.bundleID == settings.resolvedTerminalBundleID }
                    Text("Currently: \(detected?.name ?? "Terminal")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct TerminalIcon: View {
    let bundleID: String

    var body: some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "terminal")
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 300)
}
