import Foundation
import GitHubKit
import CIStatusKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WorkflowRefresh")

/// Tracks the poll-cycle cadence for re-checking repos' `hasWorkflows` flags and
/// performs the workflow-check fan-out. Repos can gain or lose CI actions after
/// initial sync, so this runs on launch and periodically to pick up changes.
@MainActor
final class WorkflowRefreshCoordinator {
    private var pollCyclesSinceRefresh = 0

    /// Advance the poll-cycle counter and report whether a workflow re-check is
    /// due this cycle — immediately when nothing is pollable (a broken state),
    /// otherwise every `workflowRefreshCycleInterval` cycles.
    func shouldRefreshThisCycle(hasPollableRepos: Bool) -> Bool {
        pollCyclesSinceRefresh += 1
        if !hasPollableRepos || pollCyclesSinceRefresh >= PollConfiguration.workflowRefreshCycleInterval {
            pollCyclesSinceRefresh = 0
            return true
        }
        return false
    }

    /// The outcome of a workflow re-check: the new `hasWorkflows` value per repo
    /// id (successful checks only) plus an optional user-facing error string.
    struct RefreshResult {
        var updates: [Int: Bool]
        var error: String?
    }

    /// Re-check `hasWorkflows` for the given monitored repos, reusing one client
    /// per account to avoid redundant rate-limit hits. Only successful checks
    /// contribute an update; failures preserve the existing value and surface an
    /// error. The caller applies `updates` to its repository list.
    func computeUpdates(monitoredRepos: [Repository], accounts: [Account]) async -> RefreshResult {
        // Reuse one client per account to avoid redundant rate-limit hits
        var clients: [UUID: GitHubAPIClient] = [:]
        var missingTokenAccounts: [String] = []
        for account in accounts {
            if let token = KeychainHelper.loadToken(for: account.id) {
                clients[account.id] = GitHubAPIClient(token: token)
            } else {
                missingTokenAccounts.append(account.name)
                logger.warning("No token found for account \(account.name)")
            }
        }

        var errorMessage: String?
        if !missingTokenAccounts.isEmpty {
            let names = missingTokenAccounts.joined(separator: ", ")
            errorMessage = "No token found for \(names)"
            if clients.isEmpty {
                return RefreshResult(updates: [:], error: errorMessage)
            }
        }

        // Collect results off-main; the caller applies them in one hop.
        var updates: [Int: Bool] = [:]
        for repo in monitoredRepos {
            guard let client = clients[repo.accountID] else { continue }
            guard let (owner, name) = repo.ownerAndName else { continue }

            // Only update on success; preserve existing value on failure
            do {
                let has = try await client.fetchHasWorkflows(owner: owner, repo: name)
                updates[repo.id] = has
            } catch {
                errorMessage = error.localizedDescription
                logger.warning("Failed to check workflows for \(repo.fullName): \(error.localizedDescription)")
            }
        }
        return RefreshResult(updates: updates, error: errorMessage)
    }
}
