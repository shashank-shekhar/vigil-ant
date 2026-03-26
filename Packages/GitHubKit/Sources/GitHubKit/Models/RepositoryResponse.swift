import Foundation

/// Raw GitHub API response for a repository. Mapped to the app-level
/// Repository model by the app layer (which adds accountID, isMonitored).
public struct RepositoryResponse: Codable, Sendable {
    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let isPrivate: Bool
    public let pushedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case fullName
        case defaultBranch
        case isPrivate = "private"
        case pushedAt
    }
}
