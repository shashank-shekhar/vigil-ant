import Foundation
import GitHubKit
import CIStatusKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppState")

// MARK: - Cached Status Entry

private struct CachedRepoStatus: Codable {
    /// Current schema version for cached status entries. Bump when adding/removing
    /// fields or changing the encoding of `statusRaw` / `sourceRaw`.
    static let currentVersion = 1

    /// Missing on pre-versioned entries; treat absence as `currentVersion` for
    /// backward compat with data written before this field existed.
    var version: Int?
    let repoID: Int
    let statusRaw: String
    let buildURL: URL?
    let updatedAt: Date
    let sourceRaw: String
    let duration: TimeInterval?

    init(repoID: Int, entry: RepoStatusEntry) {
        self.version = Self.currentVersion
        self.repoID = repoID
        self.statusRaw = Self.encodeStatus(entry.status.status)
        self.buildURL = entry.status.buildURL
        self.updatedAt = entry.status.updatedAt
        self.sourceRaw = Self.encodeSource(entry.status.source)
        self.duration = entry.status.duration
    }

    /// Effective version — untagged (pre-v1) entries are treated as v1.
    var effectiveVersion: Int { version ?? Self.currentVersion }

    func toBuildStatus() -> BuildStatus? {
        guard let status = Self.decodeStatus(statusRaw),
              let source = Self.decodeSource(sourceRaw) else { return nil }
        return BuildStatus(status: status, buildURL: buildURL, updatedAt: updatedAt, source: source, duration: duration)
    }

    private static func encodeStatus(_ status: BuildStatus.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .success: "success"
        case .building: "building"
        case .pending: "pending"
        case .failure: "failure"
        }
    }

    private static func decodeStatus(_ raw: String) -> BuildStatus.Status? {
        switch raw {
        case "unknown": .unknown
        case "success": .success
        case "building": .building
        case "pending": .pending
        case "failure": .failure
        default: nil
        }
    }

    private static func encodeSource(_ source: BuildStatus.Source) -> String {
        switch source {
        case .actions: "actions"
        case .commitStatus: "commitStatus"
        case .combined: "combined"
        }
    }

    private static func decodeSource(_ raw: String) -> BuildStatus.Source? {
        switch raw {
        case "actions": .actions
        case "commitStatus": .commitStatus
        case "combined": .combined
        default: nil
        }
    }
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

    // MARK: - Data Schema Versioning

    private static let currentDataSchemaVersion = 1

    // Persisted
    var accounts: [Account] = [] {
        didSet {
            saveAccounts()
            for account in accounts { aggregator.updateAccount(account) }
        }
    }
    var repositories: [Repository] = [] {
        didSet { saveRepositories() }
    }

    enum SettingsTab: Hashable {
        case accounts, repositories, general, about
    }

    var selectedSettingsTab: SettingsTab = .accounts

    private var previousStatuses: [Int: BuildStatus.Status] = [:]
    private var hasSeededPreviousStatuses = false

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

    /// Describes a build status transition event.
    enum StatusChangeEvent {
        case failure(RepoStatusEntry)
        case fixed(RepoStatusEntry)
    }

    /// Whether status data is stale (last update older than 2x poll interval).
    var isStale: Bool {
        guard let lastUpdated = aggregator.lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > 2 * pollIntervalSeconds
    }

    /// Optional callback fired when a repo transitions to or from failure.
    var onStatusChange: ((Int, StatusChangeEvent) -> Void)?

    init() {
        self.poller = StatusPoller(aggregator: aggregator)
        migrateDataIfNeeded()
        loadAccounts()
        loadRepositories()
        loadCachedStatuses()
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
        onStatusChange = { [weak self] _, event in
            guard let self else { return }
            switch event {
            case .failure(let entry):
                let account = self.accounts.first { $0.id == entry.repo.accountID }
                guard account?.notifyOnFailure ?? true else { return }
                NotificationManager.shared.notifyBuildFailure(
                    repo: entry.repo, buildURL: entry.status.buildURL
                )
            case .fixed(let entry):
                let account = self.accounts.first { $0.id == entry.repo.accountID }
                guard account?.notifyOnFixed ?? true else { return }
                NotificationManager.shared.notifyBuildFixed(
                    repo: entry.repo, buildURL: entry.status.buildURL
                )
            }
        }
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
        await poller.pollOnce(accounts: accountRepos)
        checkForNewFailures()
        saveCachedStatuses()

        // Re-check workflow flags: immediately if none have workflows (broken state),
        // otherwise periodically every 5 poll cycles to pick up changes.
        let hasAnyWorkflowRepos = repositories.contains { $0.isMonitored && $0.hasWorkflows }
        pollCyclesSinceWorkflowRefresh += 1
        if !hasAnyWorkflowRepos || pollCyclesSinceWorkflowRefresh >= 5 {
            pollCyclesSinceWorkflowRefresh = 0
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
                // Cap in-flight workflow-check requests to avoid fan-out blasts.
                // Uses a sliding window inside a single task group so a new request
                // starts as soon as any earlier one finishes.
                let maxInFlight = 15
                let accountRepos: [Repository] = await withTaskGroup(of: Repository.self) { group in
                    var iterator = repoResponses.makeIterator()
                    var collected: [Repository] = []

                    func submitNext() {
                        guard let resp = iterator.next() else { return }
                        group.addTask {
                            let parts = resp.fullName.split(separator: "/")
                            guard parts.count == 2 else {
                                return Repository(
                                    id: resp.id, fullName: resp.fullName,
                                    defaultBranch: resp.defaultBranch, isPrivate: resp.isPrivate,
                                    hasWorkflows: false, accountID: account.id, pushedAt: resp.pushedAt
                                )
                            }
                            let has = (try? await client.fetchHasWorkflows(
                                owner: String(parts[0]), repo: String(parts[1])
                            )) ?? false
                            return Repository(
                                id: resp.id, fullName: resp.fullName,
                                defaultBranch: resp.defaultBranch, isPrivate: resp.isPrivate,
                                hasWorkflows: has, accountID: account.id, pushedAt: resp.pushedAt
                            )
                        }
                    }

                    for _ in 0..<min(maxInFlight, repoResponses.count) { submitNext() }
                    while let repo = await group.next() {
                        collected.append(repo)
                        submitNext()
                    }
                    return collected
                }
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
        }
    }

    /// Attempt to refresh an expired access token using the stored refresh token.
    private func refreshToken(for accountID: UUID) async -> Bool {
        guard let refreshToken = KeychainHelper.loadRefreshToken(for: accountID) else {
            return false
        }

        let deviceFlow = DeviceFlowManager(clientID: OAuthConfig.clientID)
        do {
            let response = try await deviceFlow.refreshToken(refreshToken: refreshToken)

            // Save refresh token first — it's rotated on each use, so the old one
            // is invalidated server-side. If the access token save fails afterward,
            // the refresh token is still valid for the next attempt.
            if let newRefreshToken = response.refreshToken {
                try KeychainHelper.saveRefreshToken(newRefreshToken, for: accountID)
            }
            try KeychainHelper.save(token: response.accessToken, for: accountID)

            // Update the API client with the new access token
            await poller.updateClientToken(response.accessToken, for: accountID)
            return true
        } catch {
            logger.warning("Token refresh failed for \(accountID): \(error)")
            return false
        }
    }

    func checkForNewFailures() {
        // First check without a restored baseline seeds silently — prevents notification storm if cachedStatuses was wiped.
        if !hasSeededPreviousStatuses {
            for (repoID, entry) in aggregator.repoStatuses {
                previousStatuses[repoID] = entry.status.status
            }
            hasSeededPreviousStatuses = true
            return
        }

        var newFailureCount = 0

        for (repoID, entry) in aggregator.repoStatuses {
            let previous = previousStatuses[repoID]

            // Transition to failure
            if entry.status.status == .failure && previous != .failure {
                onStatusChange?(repoID, .failure(entry))
                newFailureCount += 1
            }

            // Transition from failure to success
            if entry.status.status == .success && previous == .failure {
                onStatusChange?(repoID, .fixed(entry))
            }

            previousStatuses[repoID] = entry.status.status
        }

        // Fire a summary notification when 3+ repos fail simultaneously
        if newFailureCount >= 3 {
            NotificationManager.shared.notifyMultipleFailures(count: newFailureCount)
        }
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

    /// Re-check hasWorkflows for all monitored repos.
    /// Repos can gain or lose CI actions after initial sync, so this runs
    /// on launch and periodically (every 5 poll cycles) to pick up changes.
    private var pollCyclesSinceWorkflowRefresh = 0
    
    private func refreshWorkflowFlags() {
        let reposToCheck = repositories.filter { $0.isMonitored }
        guard !reposToCheck.isEmpty else { return }

        Task {
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
                    await MainActor.run { workflowCheckError = errorMessage }
                    return
                }
            }

            // Collect results off-main, then apply in a single MainActor hop at the end.
            var pendingUpdates: [Int: Bool] = [:]
            for repo in reposToCheck {
                guard let client = clients[repo.accountID] else { continue }
                let parts = repo.fullName.split(separator: "/")
                guard parts.count == 2 else { continue }

                // Only update on success; preserve existing value on failure
                do {
                    let has = try await client.fetchHasWorkflows(owner: String(parts[0]), repo: String(parts[1]))
                    pendingUpdates[repo.id] = has
                } catch {
                    errorMessage = error.localizedDescription
                    logger.warning("Failed to check workflows for \(repo.fullName): \(error.localizedDescription)")
                }
            }

            let updates = pendingUpdates
            let finalError = errorMessage
            await MainActor.run {
                for (repoID, has) in updates {
                    if let idx = repositories.firstIndex(where: { $0.id == repoID }),
                       repositories[idx].hasWorkflows != has {
                        repositories[idx].hasWorkflows = has
                    }
                }
                workflowCheckError = finalError
            }
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "accounts")
        }
    }

    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "accounts"),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
    }

    private func saveRepositories() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: "repositories")
        }
    }

    private func loadRepositories() {
        if let data = UserDefaults.standard.data(forKey: "repositories"),
           let decoded = try? JSONDecoder().decode([Repository].self, from: data) {
            repositories = decoded
        }
    }

    // MARK: - Status Caching

    private func saveCachedStatuses() {
        let cached = aggregator.repoStatuses.map { (repoID, entry) in
            CachedRepoStatus(repoID: repoID, entry: entry)
        }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: "cachedStatuses")
        }
    }

    private func loadCachedStatuses() {
        let data = UserDefaults.standard.data(forKey: "cachedStatuses")
        var cached: [CachedRepoStatus] = []
        if let data {
            // Decode each entry individually so a single corrupt or future-versioned
            // entry doesn't nuke the whole cache.
            if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                let decoder = JSONDecoder()
                var dropped = 0
                for raw in rawArray {
                    guard let entryData = try? JSONSerialization.data(withJSONObject: raw),
                          let entry = try? decoder.decode(CachedRepoStatus.self, from: entryData) else {
                        dropped += 1
                        continue
                    }
                    guard entry.effectiveVersion == CachedRepoStatus.currentVersion else {
                        dropped += 1
                        continue
                    }
                    cached.append(entry)
                }
                if dropped > 0 {
                    logger.warning("Dropped \(dropped) cached status entries with incompatible version or corrupt data")
                }
            } else {
                logger.warning("cachedStatuses decode failed — first poll will seed baseline without notifying")
            }
        } else if !repositories.isEmpty {
            logger.warning("cachedStatuses missing despite \(self.repositories.count) configured repos — possible container reset; first poll will seed baseline without notifying")
        }
        guard !cached.isEmpty else { return }

        let reposByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        for entry in cached {
            guard let repo = reposByID[entry.repoID],
                  let account = accountsByID[repo.accountID],
                  let buildStatus = entry.toBuildStatus() else { continue }
            aggregator.update(repo: repo, account: account, status: buildStatus)
        }

        // Seed previousStatuses so the first poll after restart doesn't
        // re-notify for failures that were already reported last session.
        for (repoID, entry) in aggregator.repoStatuses {
            previousStatuses[repoID] = entry.status.status
        }
        hasSeededPreviousStatuses = !previousStatuses.isEmpty

        logger.info("Restored \(cached.count) cached status entries")
    }

    // MARK: - Data Schema Versioning

    private func migrateDataIfNeeded() {
        let storedVersion = UserDefaults.standard.integer(forKey: "dataSchemaVersion")
        let current = Self.currentDataSchemaVersion

        if storedVersion > current {
            logger.warning("Data schema version \(storedVersion) is newer than current \(current) — attempting to load anyway")
            return
        }

        if storedVersion < current {
            migrateData(from: storedVersion)
        }

        UserDefaults.standard.set(current, forKey: "dataSchemaVersion")
    }

    private func migrateData(from oldVersion: Int) {
        var version = oldVersion
        while version < Self.currentDataSchemaVersion {
            switch version {
            case 0:
                // Version 0 → 1: Initial schema marker. No data transformation needed —
                // existing UserDefaults keys (accounts, repositories, pollInterval) are
                // already in the correct format.
                logger.info("Migrating data schema from version 0 to 1")
            default:
                logger.warning("Unknown data schema version \(version) — skipping migration step")
            }
            version += 1
        }
    }
}
