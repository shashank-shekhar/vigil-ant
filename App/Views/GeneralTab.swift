import OSLog
import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "GeneralTab")

struct GeneralTab: View {
    @Bindable var appState: AppState
    var sparkleUpdater: SparkleUpdater
    @State private var launchAtLogin = false
    @State private var logsCopyState: LogsCopyState = .idle
    @State private var consoleFilterCopied = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true
    @AppStorage("notifyOnFixed") private var notifyOnFixed = true
    @AppStorage("notifyGrouping") private var notifyGrouping = true

    private enum LogsCopyState {
        case idle, copying, copied
    }

    var body: some View {
        Form {
            Section("Polling") {
                Picker("Poll Interval", selection: $appState.pollIntervalSeconds) {
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                    Text("10 min").tag(600.0)
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logger.error("Failed to update launch at login: \(error)")
                            launchAtLogin.toggle()
                        }
                    }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $showNotifications)
                Toggle("Notify on build failure", isOn: $notifyOnFailure)
                    .disabled(!showNotifications)
                Toggle("Notify when build is fixed", isOn: $notifyOnFixed)
                    .disabled(!showNotifications)
                Toggle("Group notifications", isOn: $notifyGrouping)
                    .disabled(!showNotifications)
            }

            Section("Keyboard Shortcut") {
                KeyboardShortcuts.Recorder("Toggle Popover:", name: .togglePopover)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { sparkleUpdater.automaticallyChecksForUpdates },
                    set: { sparkleUpdater.automaticallyChecksForUpdates = $0 }
                ))
            }

            Section("Diagnostics") {
                LabeledContent {
                    Button(logsCopyLabel) {
                        copyCurrentSessionLogs()
                    }
                    .disabled(logsCopyState == .copying)
                } label: {
                    Text("Copies this session's logs to your clipboard.")
                        .foregroundStyle(.secondary)
                }

                LabeledContent {
                    Button(consoleFilterCopied ? "Filter copied!" : "Open Console") {
                        openConsoleWithFilter()
                    }
                } label: {
                    Text("Copies a subsystem filter to your clipboard — paste it into Console's search field.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openConsoleWithFilter() {
        let subsystem = Bundle.main.bundleIdentifier ?? "net.shashankshekhar.vigilant"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("subsystem:\(subsystem)", forType: .string)
        consoleFilterCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
            )
            consoleFilterCopied = false
        }
    }

    private var logsCopyLabel: String {
        switch logsCopyState {
        case .idle: "Copy Logs"
        case .copying: "Copying\u{2026}"
        case .copied: "Copied!"
        }
    }

    private func copyCurrentSessionLogs() {
        logsCopyState = .copying
        Task.detached {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let position = store.position(timeIntervalSinceLatestBoot: 0)
                let entries = try store.getEntries(at: position)
                    .compactMap { $0 as? OSLogEntryLog }
                    .map { "[\($0.date.formatted(.iso8601))] [\($0.category)] \($0.composedMessage)" }

                let text = entries.joined(separator: "\n")
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text.isEmpty ? "No logs found for this session." : text, forType: .string)
                    logsCopyState = .copied
                }
            } catch {
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Failed to read logs: \(error.localizedDescription)", forType: .string)
                    logsCopyState = .copied
                }
            }
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                logsCopyState = .idle
            }
        }
    }
}
