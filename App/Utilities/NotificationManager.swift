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
        guard UserDefaults.standard.bool(forKey: "showNotifications"),
              UserDefaults.standard.bool(forKey: "notifyOnFailure") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Build Failed"
        content.body = "\(repo.fullName) on \(repo.defaultBranch)"
        content.sound = .default
        if UserDefaults.standard.bool(forKey: "notifyGrouping") {
            content.threadIdentifier = "build-status"
        }
        if let url = buildURL {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: "build-failure-\(repo.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyBuildFixed(repo: Repository, buildURL: URL?) {
        guard UserDefaults.standard.bool(forKey: "showNotifications"),
              UserDefaults.standard.bool(forKey: "notifyOnFixed") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Build Fixed"
        content.body = "\(repo.fullName) on \(repo.defaultBranch)"
        content.sound = .default
        if UserDefaults.standard.bool(forKey: "notifyGrouping") {
            content.threadIdentifier = "build-status"
        }
        if let url = buildURL {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: "build-fixed-\(repo.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyMultipleFailures(count: Int) {
        guard UserDefaults.standard.bool(forKey: "showNotifications"),
              UserDefaults.standard.bool(forKey: "notifyOnFailure") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Multiple Build Failures"
        content.body = "\(count) repos failing"
        content.sound = .default
        if UserDefaults.standard.bool(forKey: "notifyGrouping") {
            content.threadIdentifier = "build-status"
        }

        let request = UNNotificationRequest(
            identifier: "build-failure-summary",
            content: content,
            trigger: nil
        )
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
