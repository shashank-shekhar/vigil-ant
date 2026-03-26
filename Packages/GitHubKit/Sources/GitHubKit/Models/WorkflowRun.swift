import Foundation

public struct WorkflowRun: Codable, Sendable {
    public let id: Int
    public let status: String
    public let conclusion: String?
    public let htmlUrl: URL
    public let headBranch: String
    public let path: String
    public let createdAt: Date
    public let updatedAt: Date
    public let runStartedAt: Date?
}

public struct WorkflowRunsResponse: Codable, Sendable {
    public let totalCount: Int
    public let workflowRuns: [WorkflowRun]
}

public struct WorkflowEntry: Codable, Sendable {
    public let id: Int
    public let name: String
    public let path: String
    public let state: String
}

public struct WorkflowsResponse: Codable, Sendable {
    public let totalCount: Int
    public let workflows: [WorkflowEntry]
}
