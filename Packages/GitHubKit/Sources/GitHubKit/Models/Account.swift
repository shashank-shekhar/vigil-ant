import Foundation

public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var username: String
    public var iconSymbol: String
    public var displayName: String?
    public var hideOwnerPrefix: Bool
    public var notifyOnFailure: Bool
    public var notifyOnFixed: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        iconSymbol: String = "icon-bug-ant-outline",
        displayName: String? = nil,
        hideOwnerPrefix: Bool = false,
        notifyOnFailure: Bool = true,
        notifyOnFixed: Bool = true
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.iconSymbol = iconSymbol
        self.displayName = displayName
        self.hideOwnerPrefix = hideOwnerPrefix
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnFixed = notifyOnFixed
    }

    // Backward-compatible decoding: new fields may be absent in persisted data
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        iconSymbol = try container.decode(String.self, forKey: .iconSymbol)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        hideOwnerPrefix = try container.decodeIfPresent(Bool.self, forKey: .hideOwnerPrefix) ?? false
        notifyOnFailure = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFailure) ?? true
        notifyOnFixed = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFixed) ?? true
    }

    /// The name to show in the UI — uses displayName if set, otherwise the account name.
    public var effectiveDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name
    }
}
