import Testing
import Foundation
@testable import CIStatusKit
@testable import GitHubKit

@MainActor
@Test func pollerCallsFetchForMonitoredRepos() async throws {
    let aggregator = StatusAggregator()
    var fetchedRepos: [String] = []

    let fetcher: StatusPoller.RepoFetcher = { account, repo in
        fetchedRepos.append(repo.fullName)
        return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
    }

    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let repo1 = Repository(id: 1, fullName: "acme/api", defaultBranch: "main", isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)
    let repo2 = Repository(id: 2, fullName: "acme/web", defaultBranch: "main", isPrivate: false, isMonitored: false, hasWorkflows: true, accountID: account.id)

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    await poller.pollOnce(accounts: [(account, [repo1, repo2])])

    #expect(fetchedRepos == ["acme/api"]) // only monitored repo
    #expect(aggregator.globalStatus == .success)
}

// MARK: - Eager refresh helpers

/// Actor-isolated call log so concurrent test fetchers can record attempts safely.
private actor PollerCallLog {
    private(set) var calls: [(repo: String, attempt: Int)] = []
    private var perRepoAttempts: [String: Int] = [:]

    func record(_ repo: String) -> Int {
        let next = (perRepoAttempts[repo] ?? 0) + 1
        perRepoAttempts[repo] = next
        calls.append((repo, next))
        return next
    }

    func count(for repo: String) -> Int { perRepoAttempts[repo] ?? 0 }
}

private actor PollerRefreshCounter {
    private(set) var count = 0
    func tick() { count += 1 }
}

private actor PollerTokenState {
    private var fresh = false
    var isFresh: Bool { fresh }
    func markFresh() { fresh = true }
}

@MainActor
@Test func pollerEagerRefreshOn401() async throws {
    // Given an account with several repos where fetches fail with 401 until
    // the token is refreshed. The refresher returns true and marks the token
    // fresh. Expectations:
    //   - exactly one refresh is triggered for the account (dedup'd across
    //     the concurrent fetches)
    //   - every repo ends up with a success status after retry
    //   - at least one repo is retried within the same poll cycle (the one
    //     whose initial 401 kicked off the eager refresh)
    let aggregator = StatusAggregator()
    let log = PollerCallLog()
    let refreshes = PollerRefreshCounter()
    let tokenState = PollerTokenState()

    let fetcher: StatusPoller.RepoFetcher = { _, repo in
        _ = await log.record(repo.fullName)
        if await tokenState.isFresh {
            return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
        } else {
            throw GitHubAPIError.httpError(statusCode: 401)
        }
    }

    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let repos = (1...5).map { i in
        Repository(
            id: i,
            fullName: "acme/repo-\(i)",
            defaultBranch: "main",
            isPrivate: false,
            isMonitored: true,
            hasWorkflows: true,
            accountID: account.id
        )
    }

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    await poller.setTokenRefresher { accountID in
        #expect(accountID == account.id)
        await refreshes.tick()
        await tokenState.markFresh()
        return true
    }

    await poller.pollOnce(accounts: [(account, repos)])

    #expect(await refreshes.count == 1)
    #expect(aggregator.globalStatus == .success)

    for repo in repos {
        #expect(await log.count(for: repo.fullName) >= 1)
    }
    let retries = await log.calls.filter { $0.attempt > 1 }
    #expect(!retries.isEmpty, "at least one repo should have been retried post-refresh")
}

// MARK: - Issue #26: refresh dedup across multiple accounts and retry token

/// Per-account refresh counter used to assert one-refresh-per-account even
/// under many concurrent 401s.
private actor PollerAccountRefreshCounter {
    private var counts: [UUID: Int] = [:]

    func tick(_ id: UUID) { counts[id, default: 0] += 1 }
    func count(for id: UUID) -> Int { counts[id] ?? 0 }
}

/// Models a per-account token whose "freshness" is flipped by the refresher.
/// Each fetch reads the current token value; refresh mutates it. This lets
/// the test assert that post-refresh retries see the refreshed token.
private actor PollerTokenStore {
    private var tokens: [UUID: String] = [:]
    private(set) var observedTokens: [(repo: String, token: String)] = []

    func set(_ token: String, for id: UUID) { tokens[id] = token }
    func token(for id: UUID) -> String { tokens[id] ?? "stale" }
    func observe(repo: String, token: String) { observedTokens.append((repo, token)) }
}

@MainActor
@Test func pollerRefreshDedupsPerAccountAcrossManyConcurrent401s() async throws {
    // Two accounts, many monitored repos each, every fetch initially 401s.
    // Expect: exactly one refresh invocation per account (not per repo).
    let aggregator = StatusAggregator()
    let refreshes = PollerAccountRefreshCounter()
    let tokens = PollerTokenStore()

    let accountA = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let accountB = Account(name: "Personal", username: "personal", iconSymbol: "icon-heart")
    await tokens.set("stale", for: accountA.id)
    await tokens.set("stale", for: accountB.id)

    let fetcher: StatusPoller.RepoFetcher = { account, repo in
        let current = await tokens.token(for: account.id)
        if current == "fresh" {
            return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
        }
        throw GitHubAPIError.httpError(statusCode: 401)
    }

    let reposA = (1...6).map { i in
        Repository(id: 100 + i, fullName: "work/repo-\(i)", defaultBranch: "main",
                   isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: accountA.id)
    }
    let reposB = (1...6).map { i in
        Repository(id: 200 + i, fullName: "personal/repo-\(i)", defaultBranch: "main",
                   isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: accountB.id)
    }

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    await poller.setTokenRefresher { accountID in
        await refreshes.tick(accountID)
        await tokens.set("fresh", for: accountID)
        return true
    }

    await poller.pollOnce(accounts: [(accountA, reposA), (accountB, reposB)])

    // Exactly one refresh per account despite 6 concurrent 401s each.
    #expect(await refreshes.count(for: accountA.id) == 1)
    #expect(await refreshes.count(for: accountB.id) == 1)
    #expect(aggregator.globalStatus == .success)
    #expect(aggregator.authFailedAccountIDs.isEmpty)
}

@MainActor
@Test func pollerRetryUsesRefreshedToken() async throws {
    // Fetcher observes which token it sees on each attempt. After refresh,
    // the retry must observe the new token value.
    let aggregator = StatusAggregator()
    let tokens = PollerTokenStore()
    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    await tokens.set("old-token", for: account.id)

    let fetcher: StatusPoller.RepoFetcher = { account, repo in
        let current = await tokens.token(for: account.id)
        await tokens.observe(repo: repo.fullName, token: current)
        if current == "new-token" {
            return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
        }
        throw GitHubAPIError.httpError(statusCode: 401)
    }

    let repo = Repository(id: 42, fullName: "acme/api", defaultBranch: "main",
                          isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    await poller.setTokenRefresher { accountID in
        await tokens.set("new-token", for: accountID)
        return true
    }

    await poller.pollOnce(accounts: [(account, [repo])])

    let observed = await tokens.observedTokens
    // First attempt saw the old token; post-refresh retry saw the new one.
    #expect(observed.first?.token == "old-token")
    #expect(observed.last?.token == "new-token")
    #expect(observed.contains(where: { $0.token == "new-token" }))
    #expect(aggregator.globalStatus == .success)
}

// MARK: - Issue #28: cancellation mid-poll

/// Tracks fetcher entries and allows the test to release the pending fetchers
/// once cancellation has been signalled.
private actor PollerCancellationGate {
    private var entered = 0
    private(set) var fetchesCompleted = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markEntered() { entered += 1 }
    var enteredCount: Int { entered }

    func fetchFinished() { fetchesCompleted += 1 }

    /// Resolve after cancellation by checking Task.isCancelled periodically.
    /// This avoids relying on internal poll-task structure — the outer Task
    /// used by the test is cancelled, which cascades into the child fetchers.
    func awaitCancellation() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
@Test func pollerHandlesCancellationMidPoll() async throws {
    // Start a poll whose fetchers suspend; cancel the outer task while
    // fetches are in-flight; verify no crash, aggregator isn't partially
    // populated, and a subsequent poll completes normally.
    let aggregator = StatusAggregator()
    let gate = PollerCancellationGate()

    let fetcher: StatusPoller.RepoFetcher = { _, _ in
        await gate.markEntered()
        // Suspend until the enclosing Task is cancelled.
        await gate.awaitCancellation()
        await gate.fetchFinished()
        // Propagate cancellation so the fetch is treated as failed (unknown).
        throw CancellationError()
    }

    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let repos = (1...4).map { i in
        Repository(id: i, fullName: "acme/repo-\(i)", defaultBranch: "main",
                   isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)
    }

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)

    // Capture the aggregator's state prior to the cancelled poll.
    let preRepoCount = aggregator.repoStatuses.count
    let preGlobal = aggregator.globalStatus

    let pollTask = Task { @MainActor in
        await poller.pollOnce(accounts: [(account, repos)])
    }

    // Wait until fetches have entered, then cancel.
    while await gate.enteredCount == 0 {
        try await Task.sleep(for: .milliseconds(5))
    }
    pollTask.cancel()
    await pollTask.value // Must complete without crashing.

    // Aggregator must be consistent — either untouched or fully populated
    // with the (unknown) cancellation results, never half-populated.
    let postCount = aggregator.repoStatuses.count
    #expect(postCount == preRepoCount || postCount == repos.count,
            "aggregator should not be half-updated (pre=\(preRepoCount), post=\(postCount), repos=\(repos.count))")

    // If cancellation propagated into the fetcher results, statuses will be
    // .unknown — which matches the pre-poll global. Either way, no failures
    // should have leaked through.
    #expect(aggregator.globalStatus != .failure)
    #expect(preGlobal == .unknown) // sanity

    // Subsequent poll with a working fetcher succeeds — the poller is not
    // left in a broken state by cancellation.
    let healthyFetcher: StatusPoller.RepoFetcher = { _, _ in
        BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
    }
    let healthyPoller = StatusPoller(aggregator: aggregator, fetcher: healthyFetcher)
    await healthyPoller.pollOnce(accounts: [(account, repos)])
    #expect(aggregator.globalStatus == .success)
    #expect(aggregator.repoStatuses.count == repos.count)
}
