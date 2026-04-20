import Foundation
internal import AppKit
import UserNotifications
import GitHubKit
import CIStatusKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
