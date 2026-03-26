import Testing
import Foundation
@testable import GitHubKit

@Test func decodeWorkflowRunFromJSON() throws {
    let json = """
    {
        "id": 12345,
        "status": "completed",
        "conclusion": "failure",
        "html_url": "https://github.com/acme/api/actions/runs/12345",
        "head_branch": "main",
        "path": ".github/workflows/ci.yml",
        "created_at": "2026-03-16T10:00:00Z",
        "updated_at": "2026-03-16T10:05:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let run = try decoder.decode(WorkflowRun.self, from: json)
    #expect(run.id == 12345)
    #expect(run.status == "completed")
    #expect(run.conclusion == "failure")
    #expect(run.htmlUrl.absoluteString == "https://github.com/acme/api/actions/runs/12345")
}

@Test func decodeWorkflowRunsResponse() throws {
    let json = """
    {
        "total_count": 1,
        "workflow_runs": [
            {
                "id": 99,
                "status": "completed",
                "conclusion": "success",
                "html_url": "https://github.com/acme/api/actions/runs/99",
                "head_branch": "main",
        "path": ".github/workflows/ci.yml",
                "created_at": "2026-03-16T10:00:00Z",
                "updated_at": "2026-03-16T10:05:00Z"
            }
        ]
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(WorkflowRunsResponse.self, from: json)
    #expect(response.workflowRuns.count == 1)
    #expect(response.workflowRuns[0].conclusion == "success")
}

@Test func decodeCombinedStatus() throws {
    let json = """
    {
        "state": "failure",
        "statuses": [
            {
                "state": "success",
                "target_url": "https://ci.example.com/build/1",
                "description": "Build passed",
                "context": "ci/jenkins"
            },
            {
                "state": "failure",
                "target_url": "https://ci.example.com/build/2",
                "description": "Tests failed",
                "context": "ci/test"
            }
        ],
        "sha": "abc123"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let status = try decoder.decode(CombinedStatus.self, from: json)
    #expect(status.state == "failure")
    #expect(status.statuses.count == 2)
    #expect(status.statuses[1].targetUrl?.absoluteString == "https://ci.example.com/build/2")
}
