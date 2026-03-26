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

    /// Execute a single poll cycle across all accounts and monitored repos.
    public func pollOnce(
        accounts: [(Account, [Repository])]
    ) async {
        // Phase 1: Collect results from concurrent fetches
        let results = await fetchAll(accounts: accounts)

        // Phase 2: Attempt token refresh for auth-failed accounts
        let authFailedIDs = Set(results.filter {
            if case .auth = $0.3 { return true }; return false
        }.map { $0.1.id })
        var refreshedIDs: Set<UUID> = []

        if let refresher = tokenRefresher, !authFailedIDs.isEmpty {
            for accountID in authFailedIDs {
                if await refresher(accountID) {
                    logger.info("Token refreshed for account \(accountID)")
                    refreshedIDs.insert(accountID)
                } else {
                    logger.warning("Token refresh failed for account \(accountID)")
                }
            }
        }

        // Phase 3: Retry repos for successfully refreshed accounts
        var finalResults = results.filter {
            if case .auth = $0.3, refreshedIDs.contains($0.1.id) { return false }
            return true
        }

        if !refreshedIDs.isEmpty {
            let retryAccounts = accounts.filter { refreshedIDs.contains($0.0.id) }
            let retryResults = await fetchAll(accounts: retryAccounts)
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
    private func fetchAll(
        accounts: [(Account, [Repository])]
    ) async -> [FetchResult] {
        await withTaskGroup(
            of: FetchResult?.self
        ) { group in
            for (account, repos) in accounts {
                let monitoredRepos = repos.filter { $0.isMonitored && $0.hasWorkflows }

                for repo in monitoredRepos {
                    group.addTask { [self] in
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
                                logger.warning("\(repo.fullName): authentication failed (401)")
                                issue = .auth
                            } else if case .rateLimited(let retryAfter) = apiError {
                                logger.warning("\(repo.fullName): rate limited")
                                issue = .rateLimited(retryAfter: retryAfter)
                            } else if apiError?.isNotFound == true {
                                logger.warning("\(repo.fullName): not found (404) — repo may have been deleted or transferred")
                                issue = .notFound
                            } else {
                                issue = .none
                            }
                            return (repo, account, BuildStatus(
                                status: .unknown, buildURL: nil, updatedAt: .distantPast, source: .combined
                            ), issue)
                        }
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
                logger.warning("\(repo.fullName): actions fetch failed: \(error)")
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
                logger.warning("\(repo.fullName): commit status fetch failed: \(error)")
                return nil
            }
        }()

        let run = try await runResult
        let status = try await statusResult

        logger.debug("""
            \(repo.fullName): \
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

        logger.debug("\(repo.fullName): merged status=\(String(describing: merged.status), privacy: .public) source=\(String(describing: merged.source), privacy: .public)")

        return merged
    }
}
