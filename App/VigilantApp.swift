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

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort cancellation of in-flight polling so pending requests
        // don't log errors as the process is torn down.
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await appState.stopPolling()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
    }
}
