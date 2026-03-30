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
    // Defaults for new fields
    #expect(account.displayName == nil)
    #expect(account.hideOwnerPrefix == false)
    #expect(account.notifyOnFailure == true)
    #expect(account.notifyOnFixed == true)
    #expect(account.effectiveDisplayName == "Work")
}

@Test func accountCodable() throws {
    let account = Account(
        name: "Personal",
        username: "shashank",
        iconSymbol: "icon-star",
        displayName: "My Account",
        hideOwnerPrefix: true,
        notifyOnFailure: false,
        notifyOnFixed: true
    )
    let data = try JSONEncoder().encode(account)
    let decoded = try JSONDecoder().decode(Account.self, from: data)
    #expect(decoded.id == account.id)
    #expect(decoded.name == account.name)
    #expect(decoded.username == account.username)
    #expect(decoded.iconSymbol == account.iconSymbol)
    #expect(decoded.displayName == "My Account")
    #expect(decoded.hideOwnerPrefix == true)
    #expect(decoded.notifyOnFailure == false)
    #expect(decoded.notifyOnFixed == true)
    #expect(decoded.effectiveDisplayName == "My Account")
}

@Test func accountDecodingBackwardCompat() throws {
    // Simulate legacy persisted JSON that lacks the new fields
    let legacyJSON = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "Legacy",
        "username": "old-user",
        "iconSymbol": "icon-cat"
    }
    """
    let decoded = try JSONDecoder().decode(Account.self, from: Data(legacyJSON.utf8))
    #expect(decoded.name == "Legacy")
    #expect(decoded.username == "old-user")
    #expect(decoded.iconSymbol == "icon-cat")
    #expect(decoded.displayName == nil)
    #expect(decoded.hideOwnerPrefix == false)
    #expect(decoded.notifyOnFailure == true)
    #expect(decoded.notifyOnFixed == true)
    #expect(decoded.effectiveDisplayName == "Legacy")
}
