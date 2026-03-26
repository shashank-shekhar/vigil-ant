import SwiftUI
import CIStatusKit
import KeyboardShortcuts

@main
struct VigilantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState, sparkleUpdater: appDelegate.sparkleUpdater)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vigil-ant") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let sparkleUpdater = SparkleUpdater()
    private var statusBarController: StatusBarController!
    private let crashReporter = CrashReporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "showNotifications": true,
            "notifyOnFailure": true,
            "notifyOnFixed": true,
            "notifyGrouping": true,
        ])

        let popoverView = PopoverView(
            appState: appState,
            onRefresh: { [weak self] in Task { await self?.appState.refreshNow() } }
        )

        statusBarController = StatusBarController(
            aggregator: appState.aggregator,
            popoverView: popoverView
        )

        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            self?.statusBarController.togglePopover()
        }
    }

    @objc func togglePopover() {
        statusBarController.togglePopover()
    }
}
