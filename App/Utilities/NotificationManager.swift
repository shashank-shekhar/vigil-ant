import Foundation
internal import AppKit
import UserNotifications
import GitHubKit
import CIStatusKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationManager")

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.info("Notification authorization denied by the user")
            }
        }
    }

    func notifyBuildFailure(repo: Repository, buildURL: URL?) {
        guard shouldNotify(for: "notifyOnFailure") else { return }
        let content = makeContent(
            title: "Build Failed",
            body: "\(repo.fullName) on \(repo.defaultBranch)",
            buildURL: buildURL
        )
        add(content, identifier: "build-failure-\(repo.id)")
    }

    func notifyBuildFixed(repo: Repository, buildURL: URL?) {
        guard shouldNotify(for: "notifyOnFixed") else { return }
        let content = makeContent(
            title: "Build Fixed",
            body: "\(repo.fullName) on \(repo.defaultBranch)",
            buildURL: buildURL
        )
        add(content, identifier: "build-fixed-\(repo.id)")
    }

    func notifyMultipleFailures(count: Int) {
        guard shouldNotify(for: "notifyOnFailure") else { return }
        let content = makeContent(
            title: "Multiple Build Failures",
            body: "\(count) repos failing",
            buildURL: nil
        )
        add(content, identifier: "build-failure-summary")
    }

    /// Notify the user that an account can no longer be refreshed and needs
    /// re-authentication. Only the account's public handle is included — never
    /// a token or refresh token. Gated on the master notifications switch only,
    /// since this is an account-health alert rather than a build event.
    func notifyAuthFailure(account: Account) {
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }
        let content = makeContent(
            title: "Account Needs Re-authentication",
            body: "Sign in again to keep monitoring @\(account.username).",
            buildURL: nil
        )
        add(content, identifier: "auth-failure-\(account.id.uuidString)")
    }

    private func shouldNotify(for preferenceKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: "showNotifications")
            && UserDefaults.standard.bool(forKey: preferenceKey)
    }

    private func makeContent(title: String, body: String, buildURL: URL?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if UserDefaults.standard.bool(forKey: "notifyGrouping") {
            content.threadIdentifier = "build-status"
        }
        if let url = buildURL {
            content.userInfo = ["url": url.absoluteString]
        }
        return content
    }

    private func add(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Open build URL when notification is clicked
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
