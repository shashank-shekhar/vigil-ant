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
