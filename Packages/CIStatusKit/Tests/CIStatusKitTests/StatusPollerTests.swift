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

// MARK: - 404 handling (deleted / transferred repos)

/// A 404 from a repo fetch should be reported in `PollResult.notFoundRepoIDs`
/// so AppState can track repeated 404s and flip the repo to `isMissing`.
/// Successful fetches should land in `successfulRepoIDs` so AppState can
/// reset streak counters.
@MainActor
@Test func pollerReportsNotFoundAndSuccessInPollResult() async throws {
    let aggregator = StatusAggregator()
    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let liveRepo = Repository(id: 1, fullName: "acme/alive", defaultBranch: "main", isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)
    let deletedRepo = Repository(id: 2, fullName: "acme/gone", defaultBranch: "main", isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)

    let fetcher: StatusPoller.RepoFetcher = { _, repo in
        if repo.id == deletedRepo.id {
            throw GitHubAPIError.httpError(statusCode: 404)
        }
        return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
    }

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    let result = await poller.pollOnce(accounts: [(account, [liveRepo, deletedRepo])])

    #expect(result.notFoundRepoIDs == [deletedRepo.id])
    #expect(result.successfulRepoIDs == [liveRepo.id])
    #expect(aggregator.notFoundRepoIDs == [deletedRepo.id])
}

/// A 404 must NOT trigger a token refresh — 404 means the repo is gone,
/// not that the token is bad. Only 401 should route through the refresher.
@MainActor
@Test func pollerDoesNotRefreshTokenOn404() async throws {
    let aggregator = StatusAggregator()
    let refreshes = PollerRefreshCounter()

    let fetcher: StatusPoller.RepoFetcher = { _, _ in
        throw GitHubAPIError.httpError(statusCode: 404)
    }

    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let repo = Repository(id: 42, fullName: "acme/gone", defaultBranch: "main", isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)
    await poller.setTokenRefresher { _ in
        await refreshes.tick()
        return true
    }

    _ = await poller.pollOnce(accounts: [(account, [repo])])

    #expect(await refreshes.count == 0, "404s must not trigger token refresh")
    #expect(aggregator.notFoundRepoIDs == [repo.id])
}

/// Simulates the AppState-side counter logic against real `PollResult`
/// values over multiple poll cycles: repeated 404s should accumulate past
/// the threshold, while any successful fetch in between resets the streak.
/// Keeps the test in the poller layer by inlining the counter logic.
@MainActor
@Test func consecutive404sAccumulateAndResetOnSuccess() async throws {
    let aggregator = StatusAggregator()
    let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
    let repo = Repository(id: 7, fullName: "acme/flaky", defaultBranch: "main", isPrivate: false, isMonitored: true, hasWorkflows: true, accountID: account.id)

    // Deterministic sequence of per-cycle outcomes: three 404s → then a success.
    let outcomes = ActorBool(values: [false, false, false, true])
    let fetcher: StatusPoller.RepoFetcher = { _, _ in
        let succeed = await outcomes.next()
        if succeed {
            return BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
        }
        throw GitHubAPIError.httpError(statusCode: 404)
    }

    let poller = StatusPoller(aggregator: aggregator, fetcher: fetcher)

    // Mirror AppState's counter logic locally; threshold of 3.
    var streaks: [Int: Int] = [:]
    var isMissing = false
    let threshold = 3

    func applyResult(_ r: PollResult) {
        for id in r.successfulRepoIDs {
            streaks.removeValue(forKey: id)
            if id == repo.id { isMissing = false }
        }
        for id in r.notFoundRepoIDs {
            let n = (streaks[id] ?? 0) + 1
            streaks[id] = n
            if n >= threshold, id == repo.id { isMissing = true }
        }
    }

    // Cycle 1: 404 — counter = 1, not yet missing.
    applyResult(await poller.pollOnce(accounts: [(account, [repo])]))
    #expect(streaks[repo.id] == 1)
    #expect(!isMissing)

    // Cycle 2: 404 — counter = 2, not yet missing.
    applyResult(await poller.pollOnce(accounts: [(account, [repo])]))
    #expect(streaks[repo.id] == 2)
    #expect(!isMissing)

    // Cycle 3: 404 — counter = 3, flips to missing.
    applyResult(await poller.pollOnce(accounts: [(account, [repo])]))
    #expect(streaks[repo.id] == 3)
    #expect(isMissing)

    // Cycle 4: success — counter resets and missing clears.
    applyResult(await poller.pollOnce(accounts: [(account, [repo])]))
    #expect(streaks[repo.id] == nil)
    #expect(!isMissing)
}

/// Drains a scripted sequence of boolean outcomes; re-uses the last value
/// once the script runs out so long tests don't need to pad.
private actor ActorBool {
    private var values: [Bool]
    private var last: Bool
    init(values: [Bool]) {
        self.values = values
        self.last = values.last ?? false
    }
    func next() -> Bool {
        if values.isEmpty { return last }
        let v = values.removeFirst()
        last = v
        return v
    }
}
