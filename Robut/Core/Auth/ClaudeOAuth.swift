// ClaudeOAuth.swift — full-scope Claude sign-in via PKCE.
//
// WHY THIS EXISTS (and why setup-token didn't work):
//
// `/api/oauth/usage` is gated, in Claude Code's own code, on the token
// carrying BOTH `user:inference` AND `user:profile`. A `claude
// setup-token` is intentionally inference-only — Claude Code says so:
// "Long-lived tokens … are limited to inference-only for security
// reasons." So a setup-token can never read usage.
//
// A full browser login DOES grant `user:profile`. This runs that same
// PKCE flow — the one `claude auth login` uses — so Robut mints its OWN
// full-scope token into its OWN keychain item (see ClaudeTokenStore) and
// never touches Claude Code's credential.
//
// Every constant below was read from the shipped Claude Code binary, not
// invented. The client id is a PUBLIC PKCE client identifier (public
// clients have no secret by design); it is not a credential.
//
// NOTE ON ENDPOINTS: sign-in and token exchange hit platform.claude.com,
// which is NOT the rate-limited api.anthropic.com/api/oauth/usage. The
// login flow cannot trigger the usage rate limit.

import CryptoKit
import Foundation

/// One PKCE attempt: a random verifier, its S256 challenge, and a state
/// nonce. Generated fresh per sign-in; never persisted.
struct ClaudePKCE: Sendable, Equatable {
    let verifier: String
    let challenge: String
    let state: String

    static func generate() -> ClaudePKCE {
        let verifier = base64URL(randomBytes(32))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = base64URL(randomBytes(32))
        return ClaudePKCE(verifier: verifier, challenge: challenge, state: state)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// URL-safe base64, unpadded — the encoding PKCE (RFC 7636) requires.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum ClaudeOAuthError: Error, Equatable {
    /// The refresh token is dead — only a fresh sign-in fixes it.
    case invalidGrant
    case badResponse(String)
    case network
}

enum ClaudeOAuth {

    // MARK: - Constants (all read from the Claude Code binary)

    /// Public PKCE client id. Not a secret; embedded in every copy of
    /// Claude Code and used by the wider usage-tool ecosystem.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static let authorizeURL = "https://platform.claude.com/oauth/authorize"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    /// The manual-display redirect: the browser shows the code for the
    /// user to copy, so Robut needs no loopback server.
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"

    /// Minimal scope: exactly the two the usage endpoint checks for.
    static let scopes = "user:inference user:profile"

    // MARK: - Authorize

    /// The URL to open in the browser. `code=true` selects the flow that
    /// displays the authorization code instead of redirecting to an app.
    static func authorizationURL(pkce: ClaudePKCE) -> URL? {
        var components = URLComponents(string: authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components?.url
    }

    /// The manual-display page hands back `code#state`. Split it so the
    /// state can be verified and only the code is exchanged.
    static func splitPastedCode(_ pasted: String) -> (code: String, state: String?) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else { return (trimmed, nil) }
        let code = String(trimmed[trimmed.startIndex..<hashIndex])
        let state = String(trimmed[trimmed.index(after: hashIndex)...])
        return (code, state.isEmpty ? nil : state)
    }

    // MARK: - Token exchange

    static func exchange(
        code: String, pkce: ClaudePKCE, session: URLSession = .shared
    ) async throws -> ClaudeTokenBundle {
        try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
            "state": pkce.state,
        ], session: session)
    }

    static func refresh(
        refreshToken: String, session: URLSession = .shared
    ) async throws -> ClaudeTokenBundle {
        try await post([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], session: session)
    }

    // MARK: - Transport

    private static func post(
        _ body: [String: String], session: URLSession
    ) async throws -> ClaudeTokenBundle {
        guard let url = URL(string: tokenURL) else { throw ClaudeOAuthError.network }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeOAuthError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeOAuthError.badResponse("no HTTP response")
        }
        guard http.statusCode == 200 else {
            // invalid_grant is definitive: a dead refresh token or a
            // reused code. Anything else may be transient.
            let type = errorType(data)
            if http.statusCode == 400, type == "invalid_grant" {
                throw ClaudeOAuthError.invalidGrant
            }
            throw ClaudeOAuthError.badResponse("HTTP \(http.statusCode) \(type ?? "")")
        }

        guard let bundle = ClaudeTokenBundle(fromTokenResponse: data) else {
            throw ClaudeOAuthError.badResponse("unreadable token response")
        }
        return bundle
    }

    private static func errorType(_ data: Data) -> String? {
        struct Envelope: Decodable { let error: String?; let errorDescription: String? }
        return try? JSONDecoder().decode(Envelope.self, from: data).error
    }
}
