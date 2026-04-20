import Foundation

public struct Repository: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let isPrivate: Bool
    public var isMonitored: Bool
    public var hasWorkflows: Bool
    public let accountID: UUID
    public var pushedAt: Date?

    public init(
        id: Int,
        fullName: String,
        defaultBranch: String,
        isPrivate: Bool,
        isMonitored: Bool = false,
        hasWorkflows: Bool = false,
        accountID: UUID,
        pushedAt: Date? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.isMonitored = isMonitored
        self.hasWorkflows = hasWorkflows
        self.accountID = accountID
        self.pushedAt = pushedAt
    }

    public var ownerAndName: (owner: String, name: String)? {
        Self.parseOwnerAndName(from: fullName)
    }

    static func parseOwnerAndName(from fullName: String) -> (owner: String, name: String)? {
        let parts = fullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}
