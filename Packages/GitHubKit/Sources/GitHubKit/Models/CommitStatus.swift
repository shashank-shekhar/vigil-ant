import Foundation

public struct CommitStatusEntry: Codable, Sendable {
    public let state: String
    public let targetUrl: URL?
    public let description: String?
    public let context: String
    public let updatedAt: Date?
}

public struct CombinedStatus: Codable, Sendable {
    public let state: String
    public let statuses: [CommitStatusEntry]
    public let sha: String
}
