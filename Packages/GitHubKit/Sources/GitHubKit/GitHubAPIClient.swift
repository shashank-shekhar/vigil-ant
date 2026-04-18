import Foundation

public actor GitHubAPIClient {
    private var token: String
    private let session: URLSession
    private let baseURL: URL
    private var etagCache: LRUCache<String, String>
    private var responseCache: LRUCache<String, Data>
    private var rateLimitResetDate: Date?

    /// Default cap for per-endpoint cache entries. Keeps memory bounded over long sessions
    /// while staying well above any realistic active repo count.
    static let defaultCacheCapacity = 100

    public init(token: String, session: URLSession = .shared) {
        self.init(token: token, session: session, cacheCapacity: Self.defaultCacheCapacity)
    }

    init(token: String, session: URLSession = .shared, cacheCapacity: Int) {
        self.token = token
        self.session = session
        self.etagCache = LRUCache(capacity: cacheCapacity)
        self.responseCache = LRUCache(capacity: cacheCapacity)
        if let override = ProcessInfo.processInfo.environment["GITHUB_BASE_URL"],
           let url = URL(string: override) {
            self.baseURL = url
        } else {
            self.baseURL = URL(string: "https://api.github.com")!
        }
    }

    public func updateToken(_ newToken: String) {
        token = newToken
        etagCache.removeAll()
        responseCache.removeAll()
    }

    // Test-only snapshot of cache occupancy.
    internal var cacheCountsForTesting: (etag: Int, response: Int) {
        (etagCache.count, responseCache.count)
    }

    public func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw GitHubAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await executeRequest(request)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Returns the cached response on 304 Not Modified, or the fresh response on 200.
    /// Only returns nil if the server returns 304 and there is no cached response (should not happen).
    public func getWithETag<T: Decodable & Sendable>(_ path: String) async throws -> T? {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw GitHubAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        if let etag = etagCache.get(path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, httpResponse) = try await executeRequest(request)

        if httpResponse.statusCode == 304 {
            // Data hasn't changed — return the cached response
            if let cached = responseCache.get(path) {
                return try Self.decoder.decode(T.self, from: cached)
            }
            return nil
        }

        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            etagCache.set(path, etag)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        responseCache.set(path, data)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Performs a GET and returns the decoded body plus the next page URL from the Link header (if any).
    private func getPage<T: Decodable & Sendable>(_ url: URL) async throws -> (T, URL?) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await executeRequest(request)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try Self.decoder.decode(T.self, from: data)
        let nextURL = httpResponse.value(forHTTPHeaderField: "Link")
            .flatMap { Self.parseNextLink($0) }
        return (decoded, nextURL)
    }

    // MARK: - Request Execution with Retry & Rate Limit Handling

    /// Execute a request with exponential backoff retry for transient errors (5xx, network)
    /// and rate limit detection (403 with remaining=0, 429).
    private func executeRequest(_ request: URLRequest, maxRetries: Int = 2) async throws -> (Data, HTTPURLResponse) {
        // Pre-check: if we're rate-limited, fail fast without hitting the network
        if let resetDate = rateLimitResetDate, Date() < resetDate {
            throw GitHubAPIError.rateLimited(retryAfter: resetDate)
        }

        for attempt in 0...maxRetries {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
            }

            let data: Data
            let httpResponse: HTTPURLResponse

            do {
                let (d, response) = try await session.data(for: request)
                guard let r = response as? HTTPURLResponse else {
                    throw GitHubAPIError.invalidResponse
                }
                data = d
                httpResponse = r
            } catch let error as GitHubAPIError {
                throw error
            } catch {
                // Network-level error (timeout, DNS, connection reset) — retry
                if attempt < maxRetries { continue }
                throw error
            }

            // Update rate limit state from response headers
            updateRateLimitState(from: httpResponse)

            // Rate limited: 429 or 403 with exhausted quota
            if httpResponse.statusCode == 429 ||
               (httpResponse.statusCode == 403 && httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
                throw GitHubAPIError.rateLimited(retryAfter: rateLimitResetDate ?? Date().addingTimeInterval(60))
            }

            // Server error — retry if attempts remain
            if (500...599).contains(httpResponse.statusCode) && attempt < maxRetries {
                continue
            }

            return (data, httpResponse)
        }

        throw GitHubAPIError.invalidResponse
    }

    private func updateRateLimitState(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           remaining == "0",
           let resetStr = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = TimeInterval(resetStr) {
            rateLimitResetDate = Date(timeIntervalSince1970: resetTimestamp)
        } else if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
                  let seconds = TimeInterval(retryAfter) {
            rateLimitResetDate = Date().addingTimeInterval(seconds)
        } else if (200...299).contains(response.statusCode) {
            rateLimitResetDate = nil
        }
    }

    /// Parses the `rel="next"` URL from a GitHub `Link` header.
    static func parseNextLink(_ header: String) -> URL? {
        for part in header.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("rel=\"next\"") else { continue }
            guard let start = trimmed.firstIndex(of: "<"),
                  let end = trimmed.firstIndex(of: ">"),
                  start < end else { continue }
            let urlString = String(trimmed[trimmed.index(after: start)..<end])
            return URL(string: urlString)
        }
        return nil
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Convenience Fetch Methods

extension GitHubAPIClient {

    /// Fetch all repositories the authenticated user has access to, paginating through all pages.
    public func fetchRepositories() async throws -> [RepositoryResponse] {
        var allRepos: [RepositoryResponse] = []
        var nextURL: URL? = URL(string: baseURL.absoluteString + "/user/repos?per_page=100&sort=updated")

        while let url = nextURL {
            let (page, next): ([RepositoryResponse], URL?) = try await getPage(url)
            allRepos.append(contentsOf: page)
            nextURL = next
        }

        return allRepos
    }

    /// Fetch the latest workflow run for a repo's branch, excluding Dependabot workflows.
    /// Returns nil if 304.
    public func fetchLatestWorkflowRun(
        owner: String, repo: String, branch: String
    ) async throws -> WorkflowRun? {
        let path = "/repos/\(owner)/\(repo)/actions/runs?branch=\(branch)&per_page=5"
        guard let response: WorkflowRunsResponse = try await getWithETag(path) else {
            return nil
        }
        return response.workflowRuns.first { !$0.path.contains("dependabot") }
    }

    /// Check whether a repo has any non-Dependabot workflows configured.
    public func fetchHasWorkflows(owner: String, repo: String) async throws -> Bool {
        let response: WorkflowsResponse = try await get("/repos/\(owner)/\(repo)/actions/workflows")
        return response.workflows.contains { !$0.path.contains("dependabot") }
    }

    /// Fetch combined commit status for a ref. Returns nil if 304 (not modified).
    public func fetchCombinedStatus(
        owner: String, repo: String, ref: String
    ) async throws -> CombinedStatus? {
        try await getWithETag("/repos/\(owner)/\(repo)/commits/\(ref)/status")
    }
}

public enum GitHubAPIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
    case rateLimited(retryAfter: Date)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from GitHub API."
        case .httpError(let code): "GitHub API error (HTTP \(code))."
        case .rateLimited: "GitHub API rate limit exceeded."
        }
    }

    public var isUnauthorized: Bool {
        if case .httpError(statusCode: 401) = self { return true }
        return false
    }

    public var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    public var isNotFound: Bool {
        if case .httpError(statusCode: 404) = self { return true }
        return false
    }
}

// MARK: - LRU Cache

/// Small LRU cache used to bound the per-endpoint ETag and response dictionaries on
/// `GitHubAPIClient`. On insert when at capacity, the least-recently-used entry is evicted.
/// Reads and writes both mark an entry as most-recently-used.
struct LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    // Front of the array is least-recently-used; back is most-recently-used.
    // Fine for ~100 entries; no need for a linked list.
    private var order: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    var count: Int { storage.count }

    mutating func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ key: Key, _ value: Value) {
        if storage[key] != nil {
            storage[key] = value
            touch(key)
            return
        }
        if storage.count >= capacity, let oldest = order.first {
            storage.removeValue(forKey: oldest)
            order.removeFirst()
        }
        storage[key] = value
        order.append(key)
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
    }
}
