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
}
