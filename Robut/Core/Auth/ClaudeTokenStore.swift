// ClaudeTokenStore.swift — Robut's full-scope Claude token, in Robut's
// own keychain item.
//
// Stored as JSON under a keychain item Robut created (see RobutKeychain),
// so macOS never prompts to read it. This is the whole point of the app:
// Robut owns its credential and never reads Claude Code's.

import Foundation

/// A full-scope OAuth token plus what's needed to keep it alive.
struct ClaudeTokenBundle: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    /// Absolute expiry. Compared against an injected `now` so expiry logic
    /// is testable without waiting.
    let expiresAt: Date
    let scopes: [String]

    /// True when the access token is expired, or expires within `leeway`.
    /// Refresh proactively so a fetch never races the expiry boundary.
    func isExpired(now: Date, leeway: TimeInterval = 120) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }

    /// Whether this token can even read usage. A token missing
    /// `user:profile` is inference-only and the usage endpoint will reject
    /// it — so Robut can tell the user to re-authorize WITHOUT spending a
    /// doomed call on the rate-limited endpoint.
    var canReadUsage: Bool {
        scopes.contains("user:profile")
    }

    // MARK: - Wire decoding

    /// Build from a token-endpoint response. Tolerates `expires_in`
    /// (seconds) being absent by assuming a conservative hour.
    init?(fromTokenResponse data: Data, now: Date = Date()) {
        struct Response: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let expiresIn: Double?
            let scope: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case scope
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let access = response.accessToken, !access.isEmpty
        else { return nil }

        self.accessToken = access
        self.refreshToken = response.refreshToken
        self.expiresAt = now.addingTimeInterval(response.expiresIn ?? 3600)
        self.scopes = response.scope?
            .split(separator: " ").map(String.init) ?? []
    }

    /// Memberwise init for tests and refresh (which carries the old
    /// refresh token forward when the server omits a new one).
    init(accessToken: String, refreshToken: String?, expiresAt: Date, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

/// Persistence for the bundle. A thin, injectable seam over RobutKeychain
/// so nothing else in the app reaches into the keychain directly.
struct ClaudeTokenStore: Sendable {
    var load: @Sendable () -> ClaudeTokenBundle?
    var save: @Sendable (ClaudeTokenBundle) -> Void
    var clear: @Sendable () -> Void

    /// The real store, backed by Robut's own keychain item.
    static let keychain = ClaudeTokenStore(
        load: {
            guard let json = RobutKeychain.read(.claudeToken),
                  let data = json.data(using: .utf8),
                  let bundle = try? JSONDecoder().decode(ClaudeTokenBundle.self, from: data)
            else { return nil }
            return bundle
        },
        save: { bundle in
            guard let data = try? JSONEncoder().encode(bundle),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            try? RobutKeychain.write(json, to: .claudeToken)
        },
        clear: {
            try? RobutKeychain.delete(.claudeToken)
        }
    )
}
