import Testing
import Foundation
@testable import GitHubKit

// Mock URLProtocol for testing without network
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol.requestHandler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeTestClient(token: String = "test-token") -> GitHubAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return GitHubAPIClient(token: token, session: session)
}

// All tests using MockURLProtocol must be serialized to avoid handler conflicts
@Suite(.serialized) struct GitHubAPIClientTests {

    @Test func authorizationHeaderIsSet() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, "[]".data(using: .utf8)!)
        }

        let client = makeTestClient()
        let _: [RepositoryResponse] = try await client.get("/user/repos")
    }

    @Test func etagCachingSkips304() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["ETag": "\"abc123\""]
                )!
                return (response, "{\"total_count\":0,\"workflow_runs\":[]}".data(using: .utf8)!)
            } else {
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc123\"")
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 304,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, Data())
            }
        }

        let client = makeTestClient()
        let result1: WorkflowRunsResponse? = try await client.getWithETag("/repos/acme/api/actions/runs")
        #expect(result1 != nil)
        #expect(result1!.workflowRuns.isEmpty)

        let result2: WorkflowRunsResponse? = try await client.getWithETag("/repos/acme/api/actions/runs")
        #expect(result2 != nil) // 304 returns cached response
        #expect(result2!.workflowRuns.isEmpty)
        #expect(callCount == 2)
    }

    // Fetch method tests (in same serialized suite to share MockURLProtocol safely)

    @Test func fetchUserRepos() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            [
                {
                    "id": 1,
                    "full_name": "acme/api",
                    "default_branch": "main",
                    "private": true
                }
            ]
            """
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let client = makeTestClient()
        let repos = try await client.fetchRepositories()
        #expect(repos.count == 1)
        #expect(repos[0].fullName == "acme/api")
        #expect(repos[0].isPrivate == true)
    }

    @Test func fetchUserReposPaginated() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                let json = """
                [{"id": 1, "full_name": "acme/api", "default_branch": "main", "private": false}]
                """
                let nextURL = "https://api.github.com/user/repos?per_page=100&sort=updated&page=2"
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Link": "<\(nextURL)>; rel=\"next\""]
                )!
                return (response, json.data(using: .utf8)!)
            } else {
                let json = """
                [{"id": 2, "full_name": "acme/web", "default_branch": "main", "private": true}]
                """
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, json.data(using: .utf8)!)
            }
        }

        let client = makeTestClient()
        let repos = try await client.fetchRepositories()
        #expect(repos.count == 2)
        #expect(repos[0].fullName == "acme/api")
        #expect(repos[1].fullName == "acme/web")
        #expect(callCount == 2)
    }

    @Test func parseNextLink() {
        let header = """
        <https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last"
        """
        let url = GitHubAPIClient.parseNextLink(header)
        #expect(url?.absoluteString == "https://api.github.com/user/repos?page=2")

        #expect(GitHubAPIClient.parseNextLink("<https://example.com>; rel=\"prev\"") == nil)
        #expect(GitHubAPIClient.parseNextLink("") == nil)
    }

    @Test func fetchLatestWorkflowRun() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url!.absoluteString.contains("actions/runs"))
            let json = """
            {
                "total_count": 1,
                "workflow_runs": [{
                    "id": 42,
                    "status": "completed",
                    "conclusion": "success",
                    "html_url": "https://github.com/acme/api/actions/runs/42",
                    "head_branch": "main",
                    "path": ".github/workflows/ci.yml",
                    "created_at": "2026-03-16T10:00:00Z",
                    "updated_at": "2026-03-16T10:05:00Z"
                }]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let client = makeTestClient()
        let run = try await client.fetchLatestWorkflowRun(owner: "acme", repo: "api", branch: "main")
        #expect(run?.conclusion == "success")
    }

    @Test func etagAndResponseCachesEvictWhenAtCapacity() async throws {
        // Every request returns a fresh 200 with a unique ETag so both caches grow on each call.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"etag-\(request.url!.path)\""]
            )!
            return (response, "{\"total_count\":0,\"workflow_runs\":[]}".data(using: .utf8)!)
        }

        let capacity = 5
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = GitHubAPIClient(token: "test-token", session: session, cacheCapacity: capacity)

        // Exceed capacity by a comfortable margin.
        for i in 0..<(capacity * 3) {
            let _: WorkflowRunsResponse? = try await client.getWithETag("/repos/acme/api\(i)/actions/runs")
        }

        let counts = await client.cacheCountsForTesting
        #expect(counts.etag == capacity)
        #expect(counts.response == capacity)
    }

    @Test func fetchCombinedStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
                "state": "success",
                "statuses": [],
                "sha": "abc123"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let client = makeTestClient()
        let status = try await client.fetchCombinedStatus(owner: "acme", repo: "api", ref: "main")
        #expect(status?.state == "success")
    }
}
