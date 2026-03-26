import Foundation
import Observation
import GitHubKit

public struct RepoStatusEntry: Sendable {
    public let repo: Repository
    public let account: Account
    public let status: BuildStatus
}

@Observable
@MainActor
public final class StatusAggregator {
    public private(set) var repoStatuses: [Int: RepoStatusEntry] = [:] // keyed by repo ID
    public private(set) var accountStatuses: [UUID: BuildStatus.Status] = [:]
    public private(set) var globalStatus: BuildStatus.Status = .unknown
    public private(set) var failureCount: Int = 0
    public private(set) var failingAccountIDs: Set<UUID> = []
    public private(set) var authFailedAccountIDs: Set<UUID> = []
    public private(set) var rateLimitedAccountIDs: Set<UUID> = []
    public private(set) var rateLimitResetDate: Date?
    public private(set) var notFoundRepoIDs: Set<Int> = []
    public private(set) var lastUpdated: Date?
    public var pollIntervalSeconds: TimeInterval = 120

    // Account metadata for icon lookup
    private var accounts: [UUID: Account] = [:]

    public init() {}

    public func update(repo: Repository, account: Account, status: BuildStatus) {
        repoStatuses[repo.id] = RepoStatusEntry(repo: repo, account: account, status: status)
        accounts[account.id] = account
        recompute()
    }

    /// Update cached account metadata (e.g. after icon change) without waiting for next poll.
    public func updateAccount(_ account: Account) {
        accounts[account.id] = account
        // Update any existing repo entries that reference this account
        for (repoID, entry) in repoStatuses where entry.account.id == account.id {
            repoStatuses[repoID] = RepoStatusEntry(repo: entry.repo, account: account, status: entry.status)
        }
    }

    public func clear() {
        repoStatuses.removeAll()
        accountStatuses.removeAll()
        accounts.removeAll()
        globalStatus = .unknown
        failureCount = 0
        failingAccountIDs = []
        authFailedAccountIDs = []
        rateLimitedAccountIDs = []
        rateLimitResetDate = nil
        notFoundRepoIDs = []
        lastUpdated = nil
    }

    /// Replace the set of accounts with auth failures (called each poll cycle).
    public func setAuthFailures(_ accountIDs: Set<UUID>) {
        authFailedAccountIDs = accountIDs
    }

    /// Clear auth failure state for a specific account (e.g. after re-authentication).
    public func clearAuthFailure(for accountID: UUID) {
        authFailedAccountIDs.remove(accountID)
    }

    /// Returns accounts that have authentication failures.
    public func authFailedAccounts() -> [Account] {
        authFailedAccountIDs.compactMap { accounts[$0] }
    }

    /// Replace the set of rate-limited accounts (called each poll cycle).
    public func setRateLimits(_ accountIDs: Set<UUID>) {
        rateLimitedAccountIDs = accountIDs
    }

    /// Set the rate limit reset date (called when a rate limit error is caught).
    public func setRateLimitResetDate(_ date: Date?) {
        rateLimitResetDate = date
    }

    /// Whether the data is stale (last update older than 2x poll interval).
    public var isStale: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > 2 * pollIntervalSeconds
    }

    /// Replace the set of repos that returned 404 (deleted or transferred).
    public func setNotFoundRepos(_ repoIDs: Set<Int>) {
        notFoundRepoIDs = repoIDs
    }

    /// Returns repo entries for an account, sorted with failures first.
    public func sortedEntries(for accountID: UUID) -> [RepoStatusEntry] {
        repoStatuses.values
            .filter { $0.repo.accountID == accountID }
            .sorted { $0.status.status.severity > $1.status.status.severity }
    }

    /// Returns accounts sorted: failing accounts first, then by name.
    public func sortedAccounts() -> [Account] {
        accounts.values.sorted { a, b in
            let aFailing = failingAccountIDs.contains(a.id)
            let bFailing = failingAccountIDs.contains(b.id)
            if aFailing != bFailing { return aFailing }
            return a.name < b.name
        }
    }

    /// The icon info for the menu bar based on current state.
    public func menuBarIcon() -> (symbol: String, badgeCount: Int) {
        let defaultIcon = "icon-bug-ant-outline"
        guard failureCount > 0 else {
            return (defaultIcon, 0)
        }
        if failingAccountIDs.count == 1, let id = failingAccountIDs.first, let acct = accounts[id] {
            return (acct.iconSymbol, failureCount)
        }
        return (defaultIcon, failureCount)
    }

    private func recompute() {
        var accountWorst: [UUID: BuildStatus.Status] = [:]
        var totalFailures = 0
        var failing: Set<UUID> = []

        for entry in repoStatuses.values {
            let acctID = entry.repo.accountID
            let current = accountWorst[acctID] ?? .unknown
            if entry.status.status.severity > current.severity {
                accountWorst[acctID] = entry.status.status
            }
            if entry.status.status == .failure {
                totalFailures += 1
                failing.insert(acctID)
            }
        }

        accountStatuses = accountWorst
        failureCount = totalFailures
        failingAccountIDs = failing
        globalStatus = accountWorst.values.max(by: { $0.severity < $1.severity }) ?? .unknown
        lastUpdated = Date()
    }
}
