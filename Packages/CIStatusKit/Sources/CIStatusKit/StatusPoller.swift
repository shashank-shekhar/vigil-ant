import Foundation
import GitHubKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "net.shashankshekhar.vigilant", category: "StatusPoller")

public actor StatusPoller {
    /// Simplified fetcher for testing — takes account and repo, returns a status.
    /// The real implementation uses the internal clients dictionary.
    public typealias RepoFetcher = @Sendable (Account, Repository) async throws -> BuildStatus

    /// Called when a 401 is detected. Returns true if the token was refreshed successfully.
    public typealias TokenRefresher = @Sendable (UUID) async -> Bool

    private let aggregator: StatusAggregator
    private let fetcher: RepoFetcher?
    private var tokenRefresher: TokenRefresher?
    private var clients: [UUID: GitHubAPIClient] = [:]
    private var pollingTask: Task<Void, Never>?

    /// Per-poll, per-account token refresh state so concurrent 401s for the
    /// same account trigger only one refresh attempt; other in-flight repo
    /// fetches await the same result.
    private var refreshTasks: [UUID: Task<Bool, Never>] = [:]

    public init(aggregator: StatusAggregator, fetcher: RepoFetcher? = nil) {
        self.aggregator = aggregator
        self.fetcher = fetcher
    }

    public func setTokenRefresher(_ refresher: @escaping TokenRefresher) {
        tokenRefresher = refresher
    }

    public func setClient(_ client: GitHubAPIClient, for accountID: UUID) {
        clients[accountID] = client
    }

    public func removeClient(for accountID: UUID) {
        clients.removeValue(forKey: accountID)
    }

    public func updateClientToken(_ token: String, for accountID: UUID) async {
        await clients[accountID]?.updateToken(token)
    }

    /// Start polling on a repeating interval.
    public func startPolling(
        intervalSeconds: TimeInterval,
        accounts: @escaping @Sendable () async -> [(Account, [Repository])]
    ) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce(accounts: await accounts())
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private enum FetchIssue: Sendable {
        case none
        case auth
        case rateLimited(retryAfter: Date?)
        case notFound
    }

    private typealias FetchResult = (Repository, Account, BuildStatus, FetchIssue)

    /// Deduplicate token refresh attempts for a given account within a single
    /// poll cycle. The first caller for an account ID kicks off the refresh
    /// task; subsequent callers await the same task's result.
    private func refreshToken(for accountID: UUID) async -> Bool {
        guard let refresher = tokenRefresher else { return false }
        if let existing = refreshTasks[accountID] {
            return await existing.value
        }
        let task = Task { await refresher(accountID) }
        refreshTasks[accountID] = task
        return await task.value
    }

    /// Execute a single poll cycle across all accounts and monitored repos.
    public func pollOnce(
        accounts: [(Account, [Repository])]
    ) async {
        // Reset per-poll refresh state so a new poll cycle is free to attempt
        // a fresh refresh — the previous cycle's cached outcome is no longer
        // authoritative (e.g. clock skew, a user-initiated re-auth).
        refreshTasks = [:]

        // Phase 1: Concurrent fetch. The first 401 for an account eagerly
        // triggers a token refresh; concurrent 401s for the same account
        // dedup onto the same refresh task, and each 401'd repo retries
        // once with the refreshed token.
        let results = await fetchAll(accounts: accounts, allowEagerRefresh: true)

        // Phase 2: Any repos still auth-failed after eager refresh — either
        // the refresher wasn't configured, or the refresh failed. For each
        // such account, try a refresh (dedup'd via refreshTasks) and retry.
        let authFailedIDs = Set(results.filter {
            if case .auth = $0.3 { return true }; return false
        }.map { $0.1.id })
        var refreshedIDs: Set<UUID> = []

        if tokenRefresher != nil, !authFailedIDs.isEmpty {
            for accountID in authFailedIDs {
                if await refreshToken(for: accountID) {
                    logger.info("Token refreshed for account \(accountID)")
                    refreshedIDs.insert(accountID)
                } else {
                    logger.warning("Token refresh failed for account \(accountID)")
                }
            }
        }

        // Phase 3: Retry repos for successfully refreshed accounts.
        var finalResults = results.filter {
            if case .auth = $0.3, refreshedIDs.contains($0.1.id) { return false }
            return true
        }

        if !refreshedIDs.isEmpty {
            let retryAccounts = accounts.filter { refreshedIDs.contains($0.0.id) }
            // Already refreshed — disable eager refresh on this pass so a
            // still-failing token doesn't loop.
            let retryResults = await fetchAll(accounts: retryAccounts, allowEagerRefresh: false)
            finalResults.append(contentsOf: retryResults)
        }

        // Phase 4: Update aggregator on MainActor
        await MainActor.run {
            var authFailed: Set<UUID> = []
            var rateLimited: Set<UUID> = []
            var latestResetDate: Date?
            var notFound: Set<Int> = []
            for (repo, account, status, issue) in finalResults {
                aggregator.update(repo: repo, account: account, status: status)
                switch issue {
                case .auth: authFailed.insert(account.id)
                case .rateLimited(let retryAfter):
                    rateLimited.insert(account.id)
                    if let retryAfter {
                        if let existing = latestResetDate {
                            latestResetDate = max(existing, retryAfter)
                        } else {
                            latestResetDate = retryAfter
                        }
                    }
                case .notFound: notFound.insert(repo.id)
                case .none: break
                }
            }
            aggregator.setAuthFailures(authFailed)
            aggregator.setRateLimits(rateLimited)
            aggregator.setRateLimitResetDate(rateLimited.isEmpty ? nil : latestResetDate)
            aggregator.setNotFoundRepos(notFound)
        }
    }

    /// Fetch statuses for all monitored repos across accounts.
    /// When `allowEagerRefresh` is true, the first 401 seen per account
    /// kicks off a token refresh and that repo's fetch is retried once
    /// within the same pass.
    private func fetchAll(
        accounts: [(Account, [Repository])],
        allowEagerRefresh: Bool
    ) async -> [FetchResult] {
        await withTaskGroup(
            of: FetchResult?.self
        ) { group in
            for (account, repos) in accounts {
                let monitoredRepos = repos.filter { $0.isMonitored && $0.hasWorkflows }

                for repo in monitoredRepos {
                    group.addTask { [self] in
                        await self.fetchWithEagerRefresh(
                            account: account,
                            repo: repo,
                            allowEagerRefresh: allowEagerRefresh
                        )
                    }
                }
            }

            var collected: [FetchResult] = []
            for await result in group {
                if let r = result { collected.append(r) }
            }
            return collected
        }
    }

    /// Fetch a single repo's status. If the first attempt is a 401 and
    /// eager refresh is allowed, trigger (or await) a refresh for the
    /// account and try once more before giving up.
    private func fetchWithEagerRefresh(
        account: Account,
        repo: Repository,
        allowEagerRefresh: Bool
    ) async -> FetchResult {
        let first = await fetchOnce(account: account, repo: repo)
        guard case .auth = first.3, allowEagerRefresh, tokenRefresher != nil else {
            return first
        }

        // First 401 for this account — try to refresh (dedup'd) and retry.
        let refreshed = await refreshToken(for: account.id)
        if refreshed {
            logger.info("Token refreshed eagerly for account \(account.id)")
            return await fetchOnce(account: account, repo: repo)
        }
        return first
    }

    /// Single-shot fetch without any retry or refresh logic.
    private func fetchOnce(account: Account, repo: Repository) async -> FetchResult {
        do {
            let status: BuildStatus
            if let fetcher = self.fetcher {
                status = try await fetcher(account, repo)
            } else {
                status = try await self.fetchStatus(account: account, repo: repo)
            }
            return (repo, account, status, .none)
        } catch {
            let apiError = error as? GitHubAPIError
            let issue: FetchIssue
            if apiError?.isUnauthorized == true {
                logger.warning("\(repo.fullName, privacy: .private): authentication failed (401)")
                issue = .auth
            } else if case .rateLimited(let retryAfter) = apiError {
                logger.warning("\(repo.fullName, privacy: .private): rate limited")
                issue = .rateLimited(retryAfter: retryAfter)
            } else if apiError?.isNotFound == true {
                logger.warning("\(repo.fullName, privacy: .private): not found (404) — repo may have been deleted or transferred")
                issue = .notFound
            } else {
                issue = .none
            }
            return (repo, account, BuildStatus(
                status: .unknown, buildURL: nil, updatedAt: .distantPast, source: .combined
            ), issue)
        }
    }

    /// Default fetcher that calls the real GitHub API.
    private func fetchStatus(account: Account, repo: Repository) async throws -> BuildStatus {
        guard let client = clients[account.id] else {
            return BuildStatus(status: .unknown, buildURL: nil, updatedAt: .distantPast, source: .combined)
        }

        let parts = repo.fullName.split(separator: "/")
        let owner = String(parts[0])
        let repoName = String(parts[1])

        // Fetch both concurrently but independently — one failing shouldn't cancel the other.
        // Auth (401) and rate limit errors are rethrown so the caller can report them.
        async let runResult: WorkflowRun? = {
            do {
                return try await client.fetchLatestWorkflowRun(
                    owner: owner, repo: repoName, branch: repo.defaultBranch
                )
            } catch {
                let apiError = error as? GitHubAPIError
                if apiError?.isUnauthorized == true || apiError?.isRateLimited == true { throw error }
                logger.warning("\(repo.fullName, privacy: .private): actions fetch failed: \(error)")
                return nil
            }
        }()
        async let statusResult: CombinedStatus? = {
            do {
                return try await client.fetchCombinedStatus(
                    owner: owner, repo: repoName, ref: repo.defaultBranch
                )
            } catch {
                let apiError = error as? GitHubAPIError
                if apiError?.isUnauthorized == true || apiError?.isRateLimited == true { throw error }
                logger.warning("\(repo.fullName, privacy: .private): commit status fetch failed: \(error)")
                return nil
            }
        }()

        let run = try await runResult
        let status = try await statusResult

        logger.debug("""
            \(repo.fullName, privacy: .private): \
            actions=\(run?.conclusion ?? "nil", privacy: .public) \
            path=\(run?.path ?? "none", privacy: .public) \
            commitStatus=\(status?.state ?? "nil", privacy: .public) \
            statusCount=\(status?.statuses.count ?? 0)
            """)

        // Use the most recent timestamp from the API responses, not the poll time.
        // If neither source has a date, use distantPast so repos with no CI data
        // don't appear as recently active.
        let apiDate = [run?.updatedAt, status?.statuses.first?.updatedAt]
            .compactMap { $0 }
            .max() ?? .distantPast

        // GitHub returns "pending" as the default state when a commit has zero status checks.
        // Treat that as no data rather than a real pending status.
        let effectiveCommitState: String? = (status?.statuses.isEmpty == false) ? status?.state : nil

        let merged = BuildStatus.merge(
            actionsConclusion: run?.conclusion,
            actionsRunStatus: run?.status,
            actionsRunStartedAt: run?.runStartedAt,
            actionsUpdatedAt: run?.updatedAt,
            commitStatusState: effectiveCommitState,
            actionsURL: run?.htmlUrl,
            commitStatusURL: status?.statuses.first(where: { $0.state == "failure" })?.targetUrl,
            updatedAt: apiDate
        )

        logger.debug("\(repo.fullName, privacy: .private): merged status=\(String(describing: merged.status), privacy: .public) source=\(String(describing: merged.source), privacy: .public)")

        return merged
    }
}
