// ClaudeUsageSourceTests.swift — the Claude provider.
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
            url: request.url ?? ClaudeUsageSource.defaultEndpoint,
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

@Suite("Claude usage source")
struct ClaudeUsageSourceTests {

    private func source(
        json: String = "{}",
        status: Int = 200,
        headers: [String: String] = [:],
        token: String? = "synthetic-token",
        scopes: [String] = ["user:inference", "user:profile"],
        authStatus: ClaudeCLI.AuthStatus? = nil
    ) -> ClaudeUsageSource {
        ClaudeUsageSource(
            store: syntheticClaudeStore(token: token, scopes: scopes),
            authStatus: { authStatus },
            session: StubURLProtocol.stub(status: status, json: json, headers: headers)
        )
    }

    private let fullPayload = """
    {
      "five_hour":      { "utilization": 42.0, "resets_at": 1800005000 },
      "seven_day":      { "utilization": 18.0, "resets_at": 1800400000 },
      "seven_day_opus": { "utilization":  5.0, "resets_at": 1800400000 }
    }
    """

    @Test("All three Claude windows are surfaced")
    func allWindows() async throws {
        let state = await source(json: fullPayload).fetch(now: t0)
        let snapshot = try #require(state.snapshot)

        #expect(snapshot.provider == .claude)
        #expect(snapshot.windows.count == 3)
        // Session sorts first — it bites soonest.
        #expect(snapshot.windows.first?.kind == .session)
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.42) < 0.0001)
    }

    @Test("The two weekly windows do not collide on id")
    func weeklyWindowsAreDistinct() async throws {
        // Both are seven-day windows. Before `variant` existed they'd
        // share an id, so one would silently overwrite the other's
        // history and the pace verdict would be nonsense.
        let state = await source(json: fullPayload).fetch(now: t0)
        let snapshot = try #require(state.snapshot)

        let weeklies = snapshot.windows.filter { $0.kind == .weekly }
        #expect(weeklies.count == 2)
        #expect(Set(weeklies.map(\.id)).count == 2)
        #expect(weeklies.contains { $0.id == "claude.weekly" })
        #expect(weeklies.contains { $0.id == "claude.weekly.Opus" })
        #expect(weeklies.contains { $0.label.contains("Opus") })
    }

    @Test("A missing Opus window is fine — not every plan has one")
    func opusOptional() async throws {
        let json = #"{"five_hour":{"utilization":10,"resets_at":1800005000}}"#
        let snapshot = try #require(await source(json: json).fetch(now: t0).snapshot)
        #expect(snapshot.windows.count == 1)
    }

    @Test("resets_at is accepted as an ISO-8601 string too")
    func isoResetDate() async throws {
        let json = #"{"seven_day":{"utilization":50,"resets_at":"2026-07-26T05:53:00Z"}}"#
        let snapshot = try #require(await source(json: json).fetch(now: t0).snapshot)
        let window = try #require(snapshot.windows.first)
        #expect(window.resetsAt > Date(timeIntervalSince1970: 1_785_000_000))
    }

    @Test("utilization_percent is accepted as an alias")
    func utilizationAlias() async throws {
        let json = #"{"five_hour":{"utilization_percent":33,"resets_at":1800005000}}"#
        let snapshot = try #require(await source(json: json).fetch(now: t0).snapshot)
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.33) < 0.0001)
    }

    @Test("Utilization is clamped into 0...1")
    func clamped() async throws {
        let json = #"{"five_hour":{"utilization":250,"resets_at":1800005000}}"#
        let snapshot = try #require(await source(json: json).fetch(now: t0).snapshot)
        #expect(snapshot.windows.first?.usedFraction == 1.0)
    }

    @Test("A rejected token is NEVER retried automatically", arguments: [401, 403])
    func rejectedToken(status: Int) async {
        // The bug this guards: retrying a rejected credential on the
        // refresh timer got the machine IP-rate-limited by Anthropic.
        let body = #"{"error":{"type":"authentication_error","message":"nope"}}"#
        let state = await source(json: body, status: status).fetch(now: t0)

        guard case .failed(let reason, let retry) = state else {
            Issue.record("Expected .failed for HTTP \(status)"); return
        }
        #expect(retry == .userAction)
        // Surfaces Anthropic's error type so the cause is diagnosable.
        #expect(reason.contains("authentication_error"))
    }

    @Test("A rate limit backs off rather than hammering")
    func rateLimited() async {
        let state = await source(json: "{}", status: 429).fetch(now: t0)
        guard case .failed(_, let retry) = state else {
            Issue.record("Expected .failed for HTTP 429"); return
        }
        #expect(retry == .after(RetryPolicy.defaultRateLimitPause))
    }

    @Test("A Retry-After header is honoured over the default pause")
    func honoursRetryAfter() async {
        let state = await source(
            json: "{}", status: 429, headers: ["Retry-After": "120"]
        ).fetch(now: t0)

        guard case .failed(_, let retry) = state else {
            Issue.record("Expected .failed for HTTP 429"); return
        }
        #expect(retry == .after(120))
    }

    @Test("Server errors surface the status and back off")
    func serverError() async {
        let state = await source(json: "{}", status: 503).fetch(now: t0)
        guard case .failed(let reason, let retry) = state else {
            Issue.record("Expected .failed for HTTP 503"); return
        }
        #expect(reason.contains("503"))
        #expect(retry == .after(5 * 60))
    }

    @Test("Unreadable JSON fails without leaking the body")
    func garbageResponse() async {
        let state = await source(json: #"{"unexpected":true}"#).fetch(now: t0)
        guard case .failed = state else {
            Issue.record("Expected .failed when no windows could be read"); return
        }
    }

    @Test("Signed in but no token yet points at the one command that fixes it")
    func needsToken() async {
        // Only meaningful when the CLI is actually present on this machine;
        // otherwise the source correctly reports notConfigured instead.
        guard ClaudeCLI.isInstalled else { return }
        let state = await source(
            token: nil,
            authStatus: ClaudeCLI.AuthStatus(loggedIn: true, subscriptionType: "synthetic")
        ).fetch(now: t0)

        guard case .failed(let reason, let retry) = state else {
            Issue.record("Expected .failed prompting for sign-in"); return
        }
        #expect(reason.lowercased().contains("sign in"))
        // Nothing to poll for — only the user signing in changes this.
        #expect(retry == .userAction)
    }

    @Test("An inference-only token is rejected WITHOUT calling the endpoint")
    func inferenceOnlyTokenNeverCallsEndpoint() async {
        // The crux of the whole saga: a token missing user:profile cannot
        // read usage, and Robut must know that from the scopes rather than
        // spending a doomed call on the rate-limited endpoint. The stub is
        // set to 200, so if the endpoint were called the test would read
        // as ready — it must instead short-circuit to .userAction.
        let state = await source(
            json: fullPayload, status: 200, scopes: ["user:inference"]
        ).fetch(now: t0)

        guard case .failed(_, let retry) = state else {
            Issue.record("Expected .failed for an inference-only token"); return
        }
        #expect(retry == .userAction)
    }

    @Test("Signed out reads as not-configured, never as an error")
    func signedOut() async {
        let state = await source(
            token: nil,
            authStatus: ClaudeCLI.AuthStatus(loggedIn: false, subscriptionType: nil)
        ).fetch(now: t0)

        guard case .notConfigured = state else {
            Issue.record("Expected .notConfigured when signed out"); return
        }
    }
}
