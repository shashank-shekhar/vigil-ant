import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "GeneralTab")

struct GeneralTab: View {
    @Bindable var appState: AppState
    var sparkleUpdater: SparkleUpdater
    @State private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true
    @AppStorage("notifyOnFixed") private var notifyOnFixed = true
    @AppStorage("notifyGrouping") private var notifyGrouping = true

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
                Button("Check for Updates…") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
