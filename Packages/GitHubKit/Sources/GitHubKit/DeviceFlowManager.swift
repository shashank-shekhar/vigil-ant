import Foundation
import os
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "net.shashankshekhar.vigilant", category: "DeviceFlowManager")

public struct DeviceCode: Sendable, Codable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    public init(deviceCode: String, userCode: String, verificationURI: URL, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public enum DeviceFlowError: Error, LocalizedError, Equatable {
    case tokenExpired
    case accessDenied
    case deviceFlowDisabled
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .tokenExpired: "Code expired. Please try again."
        case .accessDenied: "Authorization was denied."
        case .deviceFlowDisabled: "Device flow is not enabled for this GitHub App. Enable it in GitHub App Settings."
        case .requestFailed(let msg): "Request failed: \(msg)"
        }
    }
}

public struct TokenResponse: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?

    public init(accessToken: String, refreshToken: String? = nil, expiresIn: Int? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

public struct DeviceFlowManager: Sendable {
    private let clientID: String

    /// Base URL for OAuth endpoints (github.com in production).
    private static var authBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["GITHUB_BASE_URL"],
           let url = URL(string: override) { return url }
        return URL(string: "https://github.com")!
    }

    /// Base URL for API endpoints (api.github.com in production).
    private static var apiBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["GITHUB_BASE_URL"],
           let url = URL(string: override) { return url }
        return URL(string: "https://api.github.com")!
    }

    public init(clientID: String) {
        self.clientID = clientID
    }

    public func requestDeviceCode(session: URLSession = .shared) async throws -> DeviceCode {
        var request = URLRequest(url: Self.authBaseURL.appendingPathComponent("login/device/code"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(["client_id": clientID])

        let (data, httpResponse) = try await Self.executeWithRetry(request: request, session: session)
        let body = String(data: data, encoding: .utf8) ?? "nil"
        logger.debug("requestDeviceCode status=\(httpResponse.statusCode) response: \(body, privacy: .public)")

        // Check for error response from GitHub
        if let errorResponse = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data),
           let error = errorResponse.error {
            let message = errorResponse.errorDescription ?? error
            logger.error("requestDeviceCode error: \(message, privacy: .public)")
            if error == "device_flow_disabled" || message.contains("device flow") {
                throw DeviceFlowError.deviceFlowDisabled
            }
            throw DeviceFlowError.requestFailed(message)
        }

        do {
            return try JSONDecoder().decode(DeviceCode.self, from: data)
        } catch {
            logger.error("requestDeviceCode decode failed: \(error, privacy: .public) body: \(body, privacy: .public)")
            throw DeviceFlowError.requestFailed("Unexpected response from GitHub: \(body.prefix(200))")
        }
    }

    public func pollForToken(deviceCode: DeviceCode, session: URLSession = .shared) async throws -> TokenResponse {
        var currentInterval = deviceCode.interval

        while true {
            if currentInterval > 0 {
                try await Task.sleep(for: .seconds(currentInterval))
            }

            var request = URLRequest(url: Self.authBaseURL.appendingPathComponent("login/oauth/access_token"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            request.httpBody = Self.formEncode([
                "client_id": clientID,
                "device_code": deviceCode.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            let (data, _) = try await session.data(for: request)
            logger.debug("pollForToken response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .public)")
            let response = try JSONDecoder().decode(TokenPollResponse.self, from: data)

            if let token = response.accessToken {
                return TokenResponse(
                    accessToken: token,
                    refreshToken: response.refreshToken,
                    expiresIn: response.expiresIn
                )
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                currentInterval = response.interval ?? (currentInterval + 5)
                continue
            case "expired_token":
                throw DeviceFlowError.tokenExpired
            case "access_denied":
                throw DeviceFlowError.accessDenied
            case "device_flow_disabled":
                throw DeviceFlowError.deviceFlowDisabled
            default:
                throw DeviceFlowError.requestFailed(response.error ?? "unknown")
            }
        }
    }

    public func fetchUser(token: String, session: URLSession = .shared) async throws -> GitHubUser {
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("user"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await Self.executeWithRetry(request: request, session: session)
        if !(200...299).contains(httpResponse.statusCode) {
            throw DeviceFlowError.requestFailed("GitHub API returned HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    /// Execute a request with exponential backoff retry for transient errors (5xx, network-level).
    /// Does not retry 4xx responses. Mirrors the pattern in `GitHubAPIClient.executeRequest`.
    private static func executeWithRetry(
        request: URLRequest,
        session: URLSession,
        maxRetries: Int = 2
    ) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0...maxRetries {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
            }

            let data: Data
            let httpResponse: HTTPURLResponse

            do {
                let (d, response) = try await session.data(for: request)
                guard let r = response as? HTTPURLResponse else {
                    throw DeviceFlowError.requestFailed("Invalid response from GitHub")
                }
                data = d
                httpResponse = r
            } catch let error as DeviceFlowError {
                throw error
            } catch {
                // Network-level error (timeout, DNS, connection reset) — retry
                if attempt < maxRetries { continue }
                throw error
            }

            // Server error — retry if attempts remain; 4xx falls through.
            if (500...599).contains(httpResponse.statusCode) && attempt < maxRetries {
                continue
            }

            return (data, httpResponse)
        }

        throw DeviceFlowError.requestFailed("Exhausted retries")
    }

    private struct GitHubErrorResponse: Codable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        // percentEncodedQuery handles URL-encoding; drop the leading "?" by using it directly
        return (components.percentEncodedQuery ?? "").data(using: .utf8)!
    }

    /// Exchange a refresh token for a new access token (and rotated refresh token).
    public func refreshToken(refreshToken: String, session: URLSession = .shared) async throws -> TokenResponse {
        var request = URLRequest(url: Self.authBaseURL.appendingPathComponent("login/oauth/access_token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        let (data, _) = try await session.data(for: request)
        logger.debug("refreshToken response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .public)")

        let response = try JSONDecoder().decode(TokenPollResponse.self, from: data)

        guard let accessToken = response.accessToken else {
            throw DeviceFlowError.requestFailed(response.error ?? "Token refresh failed")
        }

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresIn: response.expiresIn
        )
    }

    private struct TokenPollResponse: Codable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let error: String?
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case error
            case interval
        }
    }
}

public struct GitHubUser: Codable, Sendable {
    public let login: String
    public let id: Int
    public let name: String?
}
