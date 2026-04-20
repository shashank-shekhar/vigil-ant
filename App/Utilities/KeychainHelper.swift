import Foundation
import Security

enum KeychainHelper {
    private static let oauthService = "\(Bundle.main.bundleIdentifier!).oauth"
    private static let refreshService = "\(Bundle.main.bundleIdentifier!).oauth.refresh"

    static func save(token: String, for accountID: UUID) throws {
        try save(token, service: oauthService, accountID: accountID)
    }

    static func loadToken(for accountID: UUID) -> String? {
        load(service: oauthService, accountID: accountID)
    }

    static func deleteToken(for accountID: UUID) {
        delete(service: oauthService, accountID: accountID)
    }

    static func saveRefreshToken(_ token: String, for accountID: UUID) throws {
        try save(token, service: refreshService, accountID: accountID)
    }

    static func loadRefreshToken(for accountID: UUID) -> String? {
        load(service: refreshService, accountID: accountID)
    }

    static func deleteRefreshToken(for accountID: UUID) {
        delete(service: refreshService, accountID: accountID)
    }

    private static func baseQuery(service: String, accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrService as String: service,
        ]
    }

    private static func save(_ token: String, service: String, accountID: UUID) throws {
        var query = baseQuery(service: service, accountID: accountID)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        // SecItemAdd fails on duplicate; remove any existing entry first.
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func load(service: String, accountID: UUID) -> String? {
        var query = baseQuery(service: service, accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(service: String, accountID: UUID) {
        let query = baseQuery(service: service, accountID: accountID)
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
