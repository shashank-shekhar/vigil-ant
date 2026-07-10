import Foundation
import GitHubKit
import CIStatusKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppState")

// MARK: - Poll Configuration

/// Tunable timing/threshold constants for polling and app lifecycle, kept in
/// one place so they're easy to find and reason about together.
enum PollConfiguration {
    /// Consecutive 404 poll cycles required before flipping a repo to
    /// `isMissing`. Guards against transient GitHub blips (e.g. a brief 404 on
    /// a renamed-and-redirected URL).
    static let missingThreshold = 3

    /// Re-check each repo's `hasWorkflows` flag every N poll cycles to pick up
    /// repos that have since added or removed GitHub Actions.
    static let workflowRefreshCycleInterval = 5

    /// Best-effort grace period allowed for in-flight polling to cancel on app
    /// termination before the process is torn down.
    static let shutdownGraceSeconds: TimeInterval = 0.5
}

@Observable
@MainActor
final class AppState {
    let aggregator = StatusAggregator()
    private(set) var poller: StatusPoller!
    let networkMonitor = NetworkMonitor()
    var showSettings = false
    var workflowCheckError: String?
    var isSyncingRepos = false

    // MARK: - Extracted Coordinators

    /// Persistence, poll-cadence, notification, and missing-repo concerns live
    /// in focused components; `AppState` orchestrates them.
    private let missingTracker = MissingRepoTracker()
    private let notificationDispatcher = NotificationDispatcher()
    private let workflowRefresh = WorkflowRefreshCoordinator()

    // Persisted
    var accounts: [Account] = [] {
        didSet {
            RepositoryPersistence.save(accounts: accounts)
            for account in accounts { aggregator.updateAccount(account) }
        }
    }
    var repositories: [Repository] = [] {
        didSet { RepositoryPersistence.save(repositories: repositories) }
    }

    enum SettingsTab: Hashable {
        case accounts, repositories, general, about
    }

    var selectedSettingsTab: SettingsTab = .accounts

    var hasCompletedOnboarding: Bool = false {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var pollIntervalSeconds: TimeInterval = 120 {
        didSet {
            UserDefaults.standard.set(pollIntervalSeconds, forKey: "pollInterval")
            aggregator.pollIntervalSeconds = pollIntervalSeconds
            restartPolling()
        }
    }

    /// Whether status data is stale (last update older than 2x poll interval).
    var isStale: Bool {
        guard let lastUpdated = aggregator.lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > 2 * pollIntervalSeconds
    }

    var hasMonitoredRepos: Bool {
        repositories.contains { $0.isMonitored }
    }

    var hasPollableRepos: Bool {
        repositories.contains { $0.isMonitored && $0.hasWorkflows }
    }

    init() {
        self.poller = StatusPoller(aggregator: aggregator)
        RepositoryPersistence.migrateIfNeeded()
        loadAccounts()
        loadRepositories()
        loadCachedStatuses()
        logLaunchInfo()
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let stored = UserDefaults.standard.double(forKey: "pollInterval")
        if stored > 0 { pollIntervalSeconds = stored }
        aggregator.pollIntervalSeconds = pollIntervalSeconds
        rebuildClients()
        setupTokenRefresher()
        refreshWorkflowFlags()
        restartPolling()

        observeNetworkChanges()

        NotificationManager.shared.requestPermission()
    }

    /// Cancel the polling task. Best-effort cleanup for app termination.
    func stopPolling() async {
        await poller.stopPolling()
    }

    func refreshNow() async {
        guard networkMonitor.isConnected else {
            logger.info("Skipping refresh — offline")
            return
        }
        let accountRepos = accounts.map { acct in
            (acct, repositories.filter { $0.accountID == acct.id })
        }
        let result = await poller.pollOnce(accounts: accountRepos)
        applyPollResult(result)
        checkForNewFailures()
        saveCachedStatuses()

        // Re-check workflow flags on the coordinator's cadence to pick up repos
        // that have since added or removed GitHub Actions.
        if workflowRefresh.shouldRefreshThisCycle(hasPollableRepos: hasPollableRepos) {
            refreshWorkflowFlags()
        }
    }

    func addAccount(_ account: Account, token: String) throws {
        try KeychainHelper.save(token: token, for: account.id)
        accounts.append(account)
        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
        Task { await poller.setClient(GitHubAPIClient(token: token), for: account.id) }
        restartPolling()
    }

    func reAuthenticateAccount(_ account: Account, token: String, refreshToken: String?) throws {
        // Save refresh token FIRST — it's rotated on each use, so the old one
        // is invalidated server-side. If the access token save fails afterward,
        // the refresh token is still valid for the next attempt.
        if let refreshToken {
            do {
                try KeychainHelper.saveRefreshToken(refreshToken, for: account.id)
            } catch {
                logger.error("Failed to save refresh token during re-auth for \(account.name): \(error)")
                throw error
            }
        }

        // Save new access token to Keychain
        do {
            try KeychainHelper.save(token: token, for: account.id)
        } catch {
            logger.error("Failed to save access token during re-auth for \(account.name): \(error)")
            throw error
        }

        // Update the poller's client with the new token
        Task { await poller.updateClientToken(token, for: account.id) }

        // Clear the auth failure state for this account
        aggregator.clearAuthFailure(for: account.id)
    }

    func removeAccount(_ account: Account, keepRepos: Bool = false) {
        KeychainHelper.deleteToken(for: account.id)
        KeychainHelper.deleteRefreshToken(for: account.id)
        accounts.removeAll { $0.id == account.id }
        if !keepRepos {
            repositories.removeAll { $0.accountID == account.id }
        }
        Task { await poller.removeClient(for: account.id) }
        restartPolling()
    }

    /// Re-fetch repositories for all accounts from GitHub, preserving monitoring preferences.
    func syncRepositories() async {
        guard !accounts.isEmpty else { return }
        isSyncingRepos = true
        defer { isSyncingRepos = false }

        let previouslyMonitored = Set(repositories.filter(\.isMonitored).map(\.id))
        var allRepos: [Repository] = []

        for account in accounts {
            guard let token = KeychainHelper.loadToken(for: account.id) else { continue }
            let client = GitHubAPIClient(token: token)

            do {
                let repoResponses = try await client.fetchRepositories()
                let accountRepos = await Self.resolveRepositories(
                    from: repoResponses, accountID: account.id, client: client
                )
                allRepos.append(contentsOf: accountRepos)
            } catch {
                logger.warning("Failed to sync repos for \(account.name): \(error)")
            }
        }

        // Preserve monitoring preferences
        for i in allRepos.indices {
            if previouslyMonitored.contains(allRepos[i].id) {
                allRepos[i].isMonitored = true
            }
        }

        // Replace repo list, keeping repos from accounts that failed to sync
        let syncedAccountIDs = Set(allRepos.map(\.accountID))
        let unsyncedRepos = repositories.filter { !syncedAccountIDs.contains($0.accountID) }
        repositories = unsyncedRepos + allRepos
    }

    // MARK: - Repository Workflow Fan-out

    /// Max concurrent `fetchHasWorkflows` checks when resolving a set of repos.
    /// Caps fan-out so syncing or adding an account doesn't blast the API.
    static let maxWorkflowChecksInFlight = 15

    /// Build a `Repository` from an API response, resolving its `hasWorkflows`
    /// flag once (false when the owner/name can't be parsed or the check fails).
    nonisolated static func makeRepository(
        from resp: RepositoryResponse,
        accountID: UUID,
        client: GitHubAPIClient
    ) async -> Repository {
        var hasWorkflows = false
        if let (owner, name) = resp.ownerAndName {
            hasWorkflows = (try? await client.fetchHasWorkflows(owner: owner, repo: name)) ?? false
        }
        return Repository(
            id: resp.id, fullName: resp.fullName,
            defaultBranch: resp.defaultBranch, isPrivate: resp.isPrivate,
            hasWorkflows: hasWorkflows, accountID: accountID, pushedAt: resp.pushedAt
        )
    }

    /// Resolve `hasWorkflows` for many repo responses concurrently, capping
    /// in-flight requests with a sliding window so a new check starts as soon as
    /// any earlier one finishes. `onProgress` is invoked on the main actor as
    /// each repo completes with the running completed/total count.
    static func resolveRepositories(
        from responses: [RepositoryResponse],
        accountID: UUID,
        client: GitHubAPIClient,
        onProgress: ((_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> [Repository] {
        await withTaskGroup(of: Repository.self) { group in
            var iterator = responses.makeIterator()
            var collected: [Repository] = []

            func submitNext() {
                guard let resp = iterator.next() else { return }
                group.addTask { await makeRepository(from: resp, accountID: accountID, client: client) }
            }

            for _ in 0..<min(maxWorkflowChecksInFlight, responses.count) { submitNext() }
            while let repo = await group.next() {
                collected.append(repo)
                onProgress?(collected.count, responses.count)
                submitNext()
            }
            return collected
        }
    }

    private func rebuildClients() {
        for account in accounts {
            if let token = KeychainHelper.loadToken(for: account.id) {
                Task { await poller.setClient(GitHubAPIClient(token: token), for: account.id) }
            }
        }
    }

    private func setupTokenRefresher() {
        Task {
            await poller.setTokenRefresher { [weak self] accountID in
                await self?.refreshToken(for: accountID) ?? false
            }
            await poller.setPollObserver { [weak self] result in
                await self?.applyPollResult(result)
            }
        }
    }

    /// Update the in-memory 404 streak counter and flip repos to `isMissing`
    /// once the threshold is reached. Called after every poll cycle.
    func applyPollResult(_ result: PollResult) {
        // Reset streaks for repos that just fetched successfully.
        for repoID in result.successfulRepoIDs {
            missingTracker.reset(repoID)
            if let idx = repositories.firstIndex(where: { $0.id == repoID }),
               repositories[idx].isMissing {
                repositories[idx].isMissing = false
            }
        }

        // Increment the streak for repos that 404'd this cycle; flip to
        // `isMissing` when we hit the threshold.
        for repoID in result.notFoundRepoIDs {
            let next = missingTracker.increment(repoID)
            if next >= PollConfiguration.missingThreshold,
               let idx = repositories.firstIndex(where: { $0.id == repoID }),
               !repositories[idx].isMissing {
                repositories[idx].isMissing = true
                logger.warning("Repo \(self.repositories[idx].fullName) marked as missing after \(next) consecutive 404s")
            }
        }
    }

    /// Remove a repo that's been confirmed missing. Clears its cached state
    /// so lingering notifications don't fire.
    func removeMissingRepo(_ repo: Repository) {
        repositories.removeAll { $0.id == repo.id }
        missingTracker.forget(repo.id)
        notificationDispatcher.forget(repoID: repo.id)
    }

    /// Attempt to refresh an expired access token using the stored refresh token.
    private func refreshToken(for accountID: UUID) async -> Bool {
        guard let refreshToken = KeychainHelper.loadRefreshToken(for: accountID) else {
            // No stored refresh token — the account can't be refreshed and must
            // be re-authenticated. Surface it via the existing auth-failed UI.
            markAuthFailed(accountID)
            return false
        }

        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)
        let response: TokenResponse
        do {
            response = try await deviceFlow.refreshToken(refreshToken: refreshToken)
        } catch {
            // The token exchange failed (e.g. the refresh token was revoked or
            // expired). Mark the account auth-failed so the UI prompts a
            // re-authentication instead of silently breaking on the next poll.
            logger.warning("Token refresh failed for \(accountID): \(error)")
            markAuthFailed(accountID)
            return false
        }

        do {
            // Save refresh token first — it's rotated on each use, so the old one
            // is invalidated server-side. If the access token save fails afterward,
            // the refresh token is still valid for the next attempt.
            if let newRefreshToken = response.refreshToken {
                try KeychainHelper.saveRefreshToken(newRefreshToken, for: accountID)
            }
            try KeychainHelper.save(token: response.accessToken, for: accountID)
        } catch {
            // We obtained fresh tokens but couldn't persist them to the Keychain,
            // leaving the account in a broken state that needs re-authentication.
            // Surface it via both the auth-failed UI and a user notification.
            // Never include the token or refresh token in what we log or show.
            logger.error("Failed to persist refreshed token for \(accountID): \(error)")
            markAuthFailed(accountID)
            if let account = accounts.first(where: { $0.id == accountID }) {
                NotificationManager.shared.notifyAuthFailure(account: account)
            }
            return false
        }

        // Update the API client with the new access token
        await poller.updateClientToken(response.accessToken, for: accountID)
        return true
    }

    /// Add an account to the aggregator's auth-failed set so the existing
    /// re-authenticate UI (AccountsTab / PopoverView) surfaces it. Additive so
    /// other accounts' auth-failed state is preserved.
    private func markAuthFailed(_ accountID: UUID) {
        aggregator.setAuthFailures(aggregator.authFailedAccountIDs.union([accountID]))
    }

    func checkForNewFailures() {
        notificationDispatcher.processChanges(
            repoStatuses: aggregator.repoStatuses, accounts: accounts
        )
    }

    private func restartPolling() {
        Task {
            await poller.startPolling(
                intervalSeconds: pollIntervalSeconds,
                accounts: { @MainActor [weak self] in
                    guard let self else { return [] }
                    return self.accounts.map { acct in
                        (acct, self.repositories.filter { $0.accountID == acct.id })
                    }
                }
            )
        }
    }

    // MARK: - Network Observation

    private func observeNetworkChanges() {
        withObservationTracking {
            _ = networkMonitor.isConnected
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.networkMonitor.isConnected {
                    await self.refreshNow()
                }
                self.observeNetworkChanges()
            }
        }
    }

    // MARK: - Workflow Flag Refresh

    /// Re-check `hasWorkflows` for all monitored repos via the coordinator, then
    /// apply the results. Repos can gain or lose CI actions after initial sync,
    /// so this runs on launch and periodically to pick up changes.
    private func refreshWorkflowFlags() {
        let reposToCheck = repositories.filter { $0.isMonitored }
        guard !reposToCheck.isEmpty else { return }

        Task {
            let result = await workflowRefresh.computeUpdates(
                monitoredRepos: reposToCheck, accounts: accounts
            )
            for (repoID, has) in result.updates {
                if let idx = repositories.firstIndex(where: { $0.id == repoID }),
                   repositories[idx].hasWorkflows != has {
                    repositories[idx].hasWorkflows = has
                }
            }
            workflowCheckError = result.error
        }
    }

    private func logLaunchInfo() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        logger.info("App launched version=\(version)")
        let summary = accounts.enumerated().map { index, account in
            let accountRepos = repositories.filter { $0.accountID == account.id }
            return "account \(index + 1): \(accountRepos.count) repos; \(accountRepos.filter(\.isMonitored).count) synced"
        }.joined(separator: " | ")
        logger.info("Repos at launch: \(self.accounts.count) accounts, \(self.repositories.count) repos total; \(summary.isEmpty ? "none" : summary)")
    }

    // MARK: - Persistence

    private func loadAccounts() {
        if let loaded = RepositoryPersistence.loadAccounts() { accounts = loaded }
    }

    private func loadRepositories() {
        if let loaded = RepositoryPersistence.loadRepositories() { repositories = loaded }
    }

    // MARK: - Status Caching

    private func saveCachedStatuses() {
        let cached = aggregator.repoStatuses.map { (repoID, entry) in
            CachedRepoStatus(repoID: repoID, entry: entry)
        }
        RepositoryPersistence.save(cachedStatuses: cached)
    }

    private func loadCachedStatuses() {
        let cached = RepositoryPersistence.loadCachedStatuses(hasConfiguredRepos: !repositories.isEmpty)
        guard !cached.isEmpty else { return }

        let reposByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        for entry in cached {
            guard let repo = reposByID[entry.repoID],
                  let account = accountsByID[repo.accountID],
                  let buildStatus = entry.toBuildStatus() else { continue }
            aggregator.update(repo: repo, account: account, status: buildStatus)
        }

        // Seed the notification baseline so the first poll after restart doesn't
        // re-notify for failures that were already reported last session.
        notificationDispatcher.seed(from: aggregator.repoStatuses)

        logger.info("Restored \(cached.count) cached status entries")
    }
}
