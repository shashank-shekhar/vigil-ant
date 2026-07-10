import Foundation

/// Tracks consecutive-404 streaks per repo so a repo is only flagged missing
/// after several failed poll cycles, guarding against transient 404s (e.g. a
/// brief 404 on a renamed-and-redirected URL). The streaks are in-memory only —
/// on launch we trust the `isMissing` flag already stored on each Repository.
@MainActor
final class MissingRepoTracker {
    private var streaks: [Int: Int] = [:]

    /// Clear a repo's streak after a successful fetch.
    func reset(_ repoID: Int) {
        streaks.removeValue(forKey: repoID)
    }

    /// Increment a repo's 404 streak and return the new count.
    func increment(_ repoID: Int) -> Int {
        let next = (streaks[repoID] ?? 0) + 1
        streaks[repoID] = next
        return next
    }

    /// Drop all tracking for a repo that's been removed.
    func forget(_ repoID: Int) {
        streaks.removeValue(forKey: repoID)
    }
}
