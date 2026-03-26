import Testing
import Foundation
@testable import GitHubKit

@Test func accountCreation() {
    let account = Account(
        name: "Work",
        username: "shashank-work",
        iconSymbol: "icon-rocket"
    )
    #expect(account.name == "Work")
    #expect(account.username == "shashank-work")
    #expect(account.iconSymbol == "icon-rocket")
    #expect(account.id != UUID())
}

@Test func accountCodable() throws {
    let account = Account(
        name: "Personal",
        username: "shashank",
        iconSymbol: "icon-star"
    )
    let data = try JSONEncoder().encode(account)
    let decoded = try JSONDecoder().decode(Account.self, from: data)
    #expect(decoded.id == account.id)
    #expect(decoded.name == account.name)
    #expect(decoded.username == account.username)
    #expect(decoded.iconSymbol == account.iconSymbol)
}
