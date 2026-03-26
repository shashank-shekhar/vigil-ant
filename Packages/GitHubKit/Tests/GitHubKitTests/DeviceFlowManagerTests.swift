import Testing
import Foundation
@testable import GitHubKit

@Suite(.serialized)
struct DeviceFlowManagerTests {

    // Mock URLProtocol for intercepting HTTP requests
    final class MockProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else { fatalError("No mock handler set") }
            let (data, response) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func requestDeviceCodeParsesResponse() async throws {
        MockProtocol.handler = { request in
            let json = """
            {
                "device_code": "abc123",
                "user_code": "WDJB-MJHT",
                "verification_uri": "https://github.com/login/device",
                "expires_in": 899,
                "interval": 5
            }
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let code = try await manager.requestDeviceCode(session: mockSession())

        #expect(code.deviceCode == "abc123")
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURI == URL(string: "https://github.com/login/device")!)
        #expect(code.expiresIn == 899)
        #expect(code.interval == 5)
    }

    @Test func pollForTokenSuccessAfterPending() async throws {
        var callCount = 0
        MockProtocol.handler = { request in
            callCount += 1
            let json: String
            if callCount < 2 {
                json = """
                {"error": "authorization_pending"}
                """
            } else {
                json = """
                {"access_token": "gho_test_token", "token_type": "bearer", "scope": "repo read:org"}
                """
            }
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let deviceCode = DeviceCode(
            deviceCode: "abc123", userCode: "WDJB-MJHT",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 899, interval: 0
        )
        let response = try await manager.pollForToken(deviceCode: deviceCode, session: mockSession())
        #expect(response.accessToken == "gho_test_token")
    }

    @Test func pollForTokenThrowsOnExpired() async throws {
        MockProtocol.handler = { request in
            let json = """
            {"error": "expired_token"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let deviceCode = DeviceCode(
            deviceCode: "abc123", userCode: "X",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 899, interval: 0
        )
        await #expect(throws: DeviceFlowError.tokenExpired) {
            try await manager.pollForToken(deviceCode: deviceCode, session: mockSession())
        }
    }

    @Test func pollForTokenThrowsOnDenied() async throws {
        MockProtocol.handler = { request in
            let json = """
            {"error": "access_denied"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let deviceCode = DeviceCode(
            deviceCode: "abc123", userCode: "X",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 899, interval: 0
        )
        await #expect(throws: DeviceFlowError.accessDenied) {
            try await manager.pollForToken(deviceCode: deviceCode, session: mockSession())
        }
    }

    @Test func pollForTokenThrowsOnDeviceFlowDisabled() async throws {
        MockProtocol.handler = { request in
            let json = """
            {"error": "device_flow_disabled"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let deviceCode = DeviceCode(
            deviceCode: "abc123", userCode: "X",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 899, interval: 0
        )
        await #expect(throws: DeviceFlowError.deviceFlowDisabled) {
            try await manager.pollForToken(deviceCode: deviceCode, session: mockSession())
        }
    }

    @Test func pollForTokenRespectsSlowDown() async throws {
        var callCount = 0
        MockProtocol.handler = { request in
            callCount += 1
            let json: String
            if callCount == 1 {
                json = """
                {"error": "slow_down", "interval": 1}
                """
            } else {
                json = """
                {"access_token": "gho_slow", "token_type": "bearer", "scope": "repo"}
                """
            }
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let deviceCode = DeviceCode(
            deviceCode: "abc123", userCode: "X",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 899, interval: 0
        )
        let response = try await manager.pollForToken(deviceCode: deviceCode, session: mockSession())
        #expect(response.accessToken == "gho_slow")
        #expect(callCount == 2)
    }

    @Test func fetchUserParsesProfile() async throws {
        MockProtocol.handler = { request in
            #expect(request.url?.path == "/user")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let json = """
            {"login": "octocat", "id": 1, "name": "The Octocat"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let user = try await manager.fetchUser(token: "test-token", session: mockSession())
        #expect(user.login == "octocat")
        #expect(user.id == 1)
        #expect(user.name == "The Octocat")
    }

    @Test func refreshTokenReturnsRotatedTokens() async throws {
        MockProtocol.handler = { request in
            #expect(request.url?.path == "/login/oauth/access_token")
            let json = """
            {"access_token": "ghu_new", "refresh_token": "ghr_new", "expires_in": 28800, "token_type": "bearer"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        let response = try await manager.refreshToken(refreshToken: "ghr_old", session: mockSession())
        #expect(response.accessToken == "ghu_new")
        #expect(response.refreshToken == "ghr_new")
        #expect(response.expiresIn == 28800)
    }

    @Test func refreshTokenThrowsOnError() async throws {
        MockProtocol.handler = { request in
            let json = """
            {"error": "bad_refresh_token"}
            """
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let manager = DeviceFlowManager(clientID: "test-client-id")
        await #expect(throws: DeviceFlowError.requestFailed("bad_refresh_token")) {
            try await manager.refreshToken(refreshToken: "ghr_expired", session: mockSession())
        }
    }
}
