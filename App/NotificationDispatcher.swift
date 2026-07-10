import Foundation
import GitHubKit
import CIStatusKit

/// Detects build-status transitions and dispatches the corresponding user
/// notifications, owning the previous-status baseline used to tell a genuinely
/// new event apart from one already reported in a prior poll or session.
@MainActor
final class NotificationDispatcher {
    private var previousStatuses: [Int: BuildStatus.Status] = [:]
    private var hasSeeded = false

    /// Seed the baseline from restored/cached statuses so the first poll after
    /// launch doesn't re-notify for failures already reported last session.
    func seed(from repoStatuses: [Int: RepoStatusEntry]) {
        for (repoID, entry) in repoStatuses {
            previousStatuses[repoID] = entry.status.status
        }
        hasSeeded = !previousStatuses.isEmpty
    }

    /// Forget a removed repo so lingering transitions don't fire.
    func forget(repoID: Int) {
        previousStatuses.removeValue(forKey: repoID)
    }

    /// Compare current statuses against the baseline and dispatch notifications
    /// for new failures / fixes (honoring per-account preferences), plus a
    /// summary when several repos fail at once.
    func processChanges(repoStatuses: [Int: RepoStatusEntry], accounts: [Account]) {
        // First check without a restored baseline seeds silently — prevents a
        // notification storm if cachedStatuses was wiped.
        if !hasSeeded {
            for (repoID, entry) in repoStatuses {
                previousStatuses[repoID] = entry.status.status
            }
            hasSeeded = true
            return
        }

        var newFailureCount = 0

        for (repoID, entry) in repoStatuses {
            let previous = previousStatuses[repoID]

            // Transition to failure
            if entry.status.status == .failure && previous != .failure {
                notifyFailure(entry, accounts: accounts)
                newFailureCount += 1
            }

            // Transition from failure to success
            if entry.status.status == .success && previous == .failure {
                notifyFixed(entry, accounts: accounts)
            }

            previousStatuses[repoID] = entry.status.status
        }

        // Fire a summary notification when 3+ repos fail simultaneously
        if newFailureCount >= 3 {
            NotificationManager.shared.notifyMultipleFailures(count: newFailureCount)
        }
    }

    private func notifyFailure(_ entry: RepoStatusEntry, accounts: [Account]) {
        let account = accounts.first { $0.id == entry.repo.accountID }
        guard account?.notifyOnFailure ?? true else { return }
        NotificationManager.shared.notifyBuildFailure(repo: entry.repo, buildURL: entry.status.buildURL)
    }

    private func notifyFixed(_ entry: RepoStatusEntry, accounts: [Account]) {
        let account = accounts.first { $0.id == entry.repo.accountID }
        guard account?.notifyOnFixed ?? true else { return }
        NotificationManager.shared.notifyBuildFixed(repo: entry.repo, buildURL: entry.status.buildURL)
    }
}
