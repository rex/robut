// ClaudeAPIUsageSourceTests.swift — the API path and the composite.
//
// The network is stubbed with a URLProtocol; the keychain and the CLI
// are injected. Nothing here touches a real credential, a real keychain
// item, or a real process. PUBLIC REPO: all payloads are synthetic.

import Foundation
import Testing

@testable import Robut

// MARK: - Stub transport

// Not `final`: the URLProtocol hooks below are class-method overrides,
// which SwiftLint's static_over_final_class rule flags on a final class.
class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var headers: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? ClaudeAPIUsageSource.defaultEndpoint,
            statusCode: Self.status, httpVersion: nil, headerFields: Self.headers
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func stub(
        status: Int = 200, json: String, headers: [String: String] = [:]
    ) -> URLSession {
        Self.status = status
        Self.body = Data(json.utf8)
        Self.headers = headers
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Claude API usage source", .serialized)
struct ClaudeAPIUsageSourceTests {

    private func source(
        json: String = "{}",
        status: Int = 200,
        headers: [String: String] = [:],
        token: String? = "synthetic-token",
        scopes: [String] = ["user:inference", "user:profile"],
        authStatus: ClaudeCLI.AuthStatus? = nil
    ) -> ClaudeAPIUsageSource {
        ClaudeAPIUsageSource(
            manager: ClaudeTokenManager(
                store: syntheticClaudeStore(token: token, scopes: scopes),
                refresher: { _ in throw ClaudeOAuthError.network }
            ),
            authStatus: { authStatus },
            session: StubURLProtocol.stub(status: status, json: json, headers: headers)
        )
    }

    private let fullPayload = """
    {
      "five_hour":      { "utilization": 42.5, "resets_at": 1800005000 },
      "seven_day":      { "utilization": 18.2, "resets_at": 1800400000 },
      "seven_day_opus": { "utilization":  5.1, "resets_at": 1800400000 }
    }
    """

    @Test("Windows arrive with FLOAT resolution — the reason this path exists")
    func floatResolution() async throws {
        let state = await source(json: fullPayload).fetch(now: t0)
        let snapshot = try #require(state.snapshot)

        #expect(snapshot.provider == .claude)
        #expect(snapshot.windows.count == 3)
        // Session sorts first — it bites soonest — and keeps its decimals.
        #expect(snapshot.windows.first?.kind == .session)
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.425) < 0.0001)
    }

    @Test("The plain and Opus weeklies do not collide on id")
    func weeklyVariantsAreDistinct() async throws {
        let state = await source(json: fullPayload).fetch(now: t0)
        let snapshot = try #require(state.snapshot)
        let ids = Set(snapshot.windows.map(\.id))
        #expect(ids.count == 3)
        #expect(ids.contains("claude.weekly"))
        #expect(ids.contains("claude.weekly.Opus"))
    }

    @Test("401 means re-auth: userAction, never a timer retry")
    func authRejectionIsUserAction() async {
        let state = await source(json: #"{"error":{"type":"permission_error"}}"#, status: 401)
            .fetch(now: t0)
        guard case .failed(_, .userAction) = state else {
            Issue.record("expected .failed(.userAction), got \(state)")
            return
        }
    }

    @Test("429 honors Retry-After, clamped to sane bounds")
    func rateLimitHonorsRetryAfter() async {
        let state = await source(
            json: "{}", status: 429, headers: ["Retry-After": "600"]
        ).fetch(now: t0)
        guard case .failed(_, .after(let pause)) = state else {
            Issue.record("expected .failed(.after), got \(state)")
            return
        }
        #expect(pause == 600)
    }

    @Test("Server errors back off without demanding sign-in")
    func serverErrorBacksOff() async {
        let state = await source(json: "{}", status: 503).fetch(now: t0)
        guard case .failed(_, .after) = state else {
            Issue.record("expected .failed(.after), got \(state)")
            return
        }
    }

    @Test("An unreadable payload backs off rather than blanking or crashing")
    func garbageBacksOff() async {
        let state = await source(json: #"{"unexpected": true}"#).fetch(now: t0)
        guard case .failed(_, .after) = state else {
            Issue.record("expected .failed(.after), got \(state)")
            return
        }
    }

    @Test("An inference-only token is rejected by scope, without a network call")
    func scopeGateBeforeNetwork() async {
        // The stub would return 200 with valid JSON — proving the request
        // was never made is the .userAction outcome itself.
        let state = await source(json: fullPayload, scopes: ["user:inference"]).fetch(now: t0)
        guard case .failed(_, .userAction) = state else {
            Issue.record("expected .failed(.userAction), got \(state)")
            return
        }
    }

    @Test("No token + Claude Code signed in = offer sign-in; signed out = calm not-configured")
    func noTokenStates() async {
        let signedIn = await source(
            token: nil,
            authStatus: ClaudeCLI.AuthStatus(loggedIn: true, subscriptionType: "max")
        ).fetch(now: t0)
        guard case .failed(_, .userAction) = signedIn else {
            Issue.record("expected sign-in offer, got \(signedIn)")
            return
        }

        let signedOut = await source(token: nil, authStatus: nil).fetch(now: t0)
        guard case .notConfigured = signedOut else {
            Issue.record("expected .notConfigured, got \(signedOut)")
            return
        }
    }
}
