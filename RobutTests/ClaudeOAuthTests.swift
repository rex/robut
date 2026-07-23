// ClaudeOAuthTests.swift — the PKCE sign-in machinery.
//
// Pure crypto + stubbed transport; no browser, no real network, no
// keychain. PUBLIC REPO: every value here is synthetic.

import CryptoKit
import Foundation
import Testing

@testable import Robut

@Suite("Claude PKCE")
struct ClaudePKCETests {

    @Test("Verifier and challenge are URL-safe base64 with no padding")
    func urlSafe() {
        let pkce = ClaudePKCE.generate()
        for value in [pkce.verifier, pkce.challenge, pkce.state] {
            #expect(!value.contains("+"))
            #expect(!value.contains("/"))
            #expect(!value.contains("="))
            #expect(!value.isEmpty)
        }
    }

    @Test("Challenge is the S256 hash of the verifier, per RFC 7636")
    func challengeIsS256OfVerifier() {
        let pkce = ClaudePKCE.generate()
        let expected = ClaudePKCE.base64URL(Data(SHA256.hash(data: Data(pkce.verifier.utf8))))
        #expect(pkce.challenge == expected)
    }

    @Test("Each sign-in gets a fresh verifier and state")
    func freshEachTime() {
        let first = ClaudePKCE.generate()
        let second = ClaudePKCE.generate()
        #expect(first.verifier != second.verifier)
        #expect(first.state != second.state)
    }
}

@Suite("Claude authorize URL")
struct ClaudeAuthorizeURLTests {

    @Test("Carries every parameter the PKCE flow requires")
    func hasAllParams() throws {
        let pkce = ClaudePKCE.generate()
        let url = try #require(ClaudeOAuth.authorizationURL(pkce: pkce))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(url.absoluteString.hasPrefix("https://platform.claude.com/oauth/authorize"))
        #expect(items["client_id"] == ClaudeOAuth.clientID)
        #expect(items["response_type"] == "code")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["state"] == pkce.state)
        #expect(items["redirect_uri"] == ClaudeOAuth.redirectURI)
        // The scope MUST include user:profile — the whole reason for this
        // flow instead of setup-token.
        #expect(items["scope"]?.contains("user:profile") ?? false)
    }

    @Test("Pasted code#state is split; a bare code is returned as-is")
    func splitsPastedCode() {
        let both = ClaudeOAuth.splitPastedCode("  abc123#xyz789  ")
        #expect(both.code == "abc123")
        #expect(both.state == "xyz789")

        let bare = ClaudeOAuth.splitPastedCode("abc123")
        #expect(bare.code == "abc123")
        #expect(bare.state == nil)
    }
}

@Suite("Claude token bundle")
struct ClaudeTokenBundleTests {

    @Test("Decodes a token-endpoint response")
    func decodes() throws {
        let json = """
        {"access_token":"at","refresh_token":"rt","expires_in":3600,
         "scope":"user:inference user:profile","token_type":"Bearer"}
        """
        let bundle = try #require(ClaudeTokenBundle(fromTokenResponse: Data(json.utf8), now: t0))
        #expect(bundle.accessToken == "at")
        #expect(bundle.refreshToken == "rt")
        #expect(bundle.scopes == ["user:inference", "user:profile"])
        #expect(abs(bundle.expiresAt.timeIntervalSince(t0) - 3600) < 1)
    }

    @Test("A response with no access token is rejected")
    func rejectsMissingToken() {
        #expect(ClaudeTokenBundle(fromTokenResponse: Data(#"{"scope":"x"}"#.utf8)) == nil)
    }

    @Test("canReadUsage requires the user:profile scope")
    func scopeGate() {
        let full = ClaudeTokenBundle(
            accessToken: "a", refreshToken: nil, expiresAt: t0, scopes: ["user:inference", "user:profile"]
        )
        let inferenceOnly = ClaudeTokenBundle(
            accessToken: "a", refreshToken: nil, expiresAt: t0, scopes: ["user:inference"]
        )
        #expect(full.canReadUsage)
        #expect(!inferenceOnly.canReadUsage)
    }

    @Test("Expiry accounts for the refresh leeway")
    func expiry() {
        let bundle = ClaudeTokenBundle(
            accessToken: "a", refreshToken: "r",
            expiresAt: t0.addingTimeInterval(3600), scopes: []
        )
        #expect(!bundle.isExpired(now: t0))
        // Within the 120s leeway of the deadline → treated as expired so
        // we refresh before a fetch can race the boundary.
        #expect(bundle.isExpired(now: t0.addingTimeInterval(3600 - 60)))
    }
}

@Suite("Claude token exchange")
struct ClaudeTokenExchangeTests {

    @Test("A 200 response yields a full-scope bundle")
    func exchangeSucceeds() async throws {
        let session = StubURLProtocol.stub(
            status: 200,
            json: #"""
            {"access_token":"at","refresh_token":"rt","expires_in":3600,"scope":"user:inference user:profile"}
            """#
        )
        let pkce = ClaudePKCE.generate()
        let bundle = try await ClaudeOAuth.exchange(code: "code", pkce: pkce, session: session)
        #expect(bundle.accessToken == "at")
        #expect(bundle.canReadUsage)
    }

    @Test("invalid_grant is a terminal error, not a retryable one")
    func invalidGrantIsTerminal() async {
        let session = StubURLProtocol.stub(status: 400, json: #"{"error":"invalid_grant"}"#)
        let pkce = ClaudePKCE.generate()
        await #expect(throws: ClaudeOAuthError.invalidGrant) {
            _ = try await ClaudeOAuth.exchange(code: "used", pkce: pkce, session: session)
        }
    }

    @Test("A refresh returns a new bundle")
    func refreshSucceeds() async throws {
        let session = StubURLProtocol.stub(
            status: 200,
            json: #"""
            {"access_token":"at2","refresh_token":"rt2",
             "expires_in":3600,"scope":"user:inference user:profile"}
            """#
        )
        let bundle = try await ClaudeOAuth.refresh(refreshToken: "old", session: session)
        #expect(bundle.accessToken == "at2")
    }
}
