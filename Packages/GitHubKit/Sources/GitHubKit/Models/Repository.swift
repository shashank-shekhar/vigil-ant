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
    /// Set to true when the repo has been confirmed missing on GitHub
    /// (deleted, transferred, or renamed). Populated by AppState after
    /// repeated 404s during polling; persisted so the UI can offer a
    /// prune action across launches.
    public var isMissing: Bool

    public init(
        id: Int,
        fullName: String,
        defaultBranch: String,
        isPrivate: Bool,
        isMonitored: Bool = false,
        hasWorkflows: Bool = false,
        accountID: UUID,
        pushedAt: Date? = nil,
        isMissing: Bool = false
    ) {
        self.id = id
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.isMonitored = isMonitored
        self.hasWorkflows = hasWorkflows
        self.accountID = accountID
        self.pushedAt = pushedAt
        self.isMissing = isMissing
    }

    private enum CodingKeys: String, CodingKey {
        case id, fullName, defaultBranch, isPrivate, isMonitored, hasWorkflows, accountID, pushedAt, isMissing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.fullName = try c.decode(String.self, forKey: .fullName)
        self.defaultBranch = try c.decode(String.self, forKey: .defaultBranch)
        self.isPrivate = try c.decode(Bool.self, forKey: .isPrivate)
        self.isMonitored = try c.decodeIfPresent(Bool.self, forKey: .isMonitored) ?? false
        self.hasWorkflows = try c.decodeIfPresent(Bool.self, forKey: .hasWorkflows) ?? false
        self.accountID = try c.decode(UUID.self, forKey: .accountID)
        self.pushedAt = try c.decodeIfPresent(Date.self, forKey: .pushedAt)
        self.isMissing = try c.decodeIfPresent(Bool.self, forKey: .isMissing) ?? false
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
