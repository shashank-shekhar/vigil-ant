import Testing
import Foundation
@testable import CIStatusKit
@testable import GitHubKit

@MainActor
@Suite struct StatusAggregatorTests {

    @Test func allPassingShowsSuccess() {
        let aggregator = StatusAggregator()
        let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
        let repo = Repository(id: 1, fullName: "acme/api", defaultBranch: "main", isPrivate: false, accountID: account.id)

        aggregator.update(
            repo: repo,
            account: account,
            status: BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions)
        )

        #expect(aggregator.globalStatus == .success)
        #expect(aggregator.failureCount == 0)
        #expect(aggregator.accountStatuses[account.id] == .success)
    }

    @Test func singleAccountFailure() {
        let aggregator = StatusAggregator()
        let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
        let repo1 = Repository(id: 1, fullName: "acme/api", defaultBranch: "main", isPrivate: false, accountID: account.id)
        let repo2 = Repository(id: 2, fullName: "acme/web", defaultBranch: "main", isPrivate: false, accountID: account.id)

        aggregator.update(repo: repo1, account: account,
            status: BuildStatus(status: .failure, buildURL: URL(string: "https://example.com")!, updatedAt: Date(), source: .actions))
        aggregator.update(repo: repo2, account: account,
            status: BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions))

        #expect(aggregator.globalStatus == .failure)
        #expect(aggregator.failureCount == 1)
        #expect(aggregator.failingAccountIDs == [account.id])
    }

    @Test func multipleAccountFailures() {
        let aggregator = StatusAggregator()
        let acct1 = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
        let acct2 = Account(name: "Personal", username: "me", iconSymbol: "icon-star")
        let repo1 = Repository(id: 1, fullName: "acme/api", defaultBranch: "main", isPrivate: false, accountID: acct1.id)
        let repo2 = Repository(id: 2, fullName: "me/app", defaultBranch: "main", isPrivate: false, accountID: acct2.id)

        aggregator.update(repo: repo1, account: acct1,
            status: BuildStatus(status: .failure, buildURL: nil, updatedAt: Date(), source: .actions))
        aggregator.update(repo: repo2, account: acct2,
            status: BuildStatus(status: .failure, buildURL: nil, updatedAt: Date(), source: .actions))

        #expect(aggregator.failureCount == 2)
        #expect(aggregator.failingAccountIDs.count == 2)
    }

    @Test func sortedReposFailingFirst() {
        let aggregator = StatusAggregator()
        let account = Account(name: "Work", username: "work", iconSymbol: "icon-rocket")
        let repoOK = Repository(id: 1, fullName: "acme/lib", defaultBranch: "main", isPrivate: false, accountID: account.id)
        let repoFail = Repository(id: 2, fullName: "acme/api", defaultBranch: "main", isPrivate: false, accountID: account.id)

        aggregator.update(repo: repoOK, account: account,
            status: BuildStatus(status: .success, buildURL: nil, updatedAt: Date(), source: .actions))
        aggregator.update(repo: repoFail, account: account,
            status: BuildStatus(status: .failure, buildURL: nil, updatedAt: Date(), source: .actions))

        let sorted = aggregator.sortedEntries(for: account.id)
        #expect(sorted.first?.repo.fullName == "acme/api") // failing first
    }
}
