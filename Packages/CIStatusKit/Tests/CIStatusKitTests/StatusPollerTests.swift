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
