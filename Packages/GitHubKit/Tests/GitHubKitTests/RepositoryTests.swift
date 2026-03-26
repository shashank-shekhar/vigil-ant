import Testing
import Foundation
@testable import GitHubKit

@Test func repositoryCreation() {
    let accountID = UUID()
    let repo = Repository(
        id: 12345,
        fullName: "acme/api-server",
        defaultBranch: "main",
        isPrivate: true,
        accountID: accountID
    )
    #expect(repo.id == 12345)
    #expect(repo.fullName == "acme/api-server")
    #expect(repo.defaultBranch == "main")
    #expect(repo.isPrivate == true)
    #expect(repo.isMonitored == false)
    #expect(repo.accountID == accountID)
}

@Test func repositoryCodable() throws {
    let repo = Repository(
        id: 99,
        fullName: "shashank/dotfiles",
        defaultBranch: "main",
        isPrivate: false,
        accountID: UUID()
    )
    let data = try JSONEncoder().encode(repo)
    let decoded = try JSONDecoder().decode(Repository.self, from: data)
    #expect(decoded.id == repo.id)
    #expect(decoded.fullName == repo.fullName)
    #expect(decoded.isMonitored == repo.isMonitored)
}
