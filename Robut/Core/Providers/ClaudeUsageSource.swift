// ClaudeUsageSource.swift — Claude subscription usage, without ever
// touching Claude Code's keychain item.
//
// HOW THE TOKEN IS OBTAINED, and why it isn't a browser OAuth flow:
//
// Anthropic ships `claude setup-token`, the official way to mint a
// long-lived token for a Claude subscription. The user runs it once and
// pastes the result into Robut, which stores it in ROBUT'S OWN keychain
// item (see RobutKeychain) and is therefore never prompted again.
//
// The alternative — implementing a PKCE browser flow — would require
// presenting Claude Code's own OAuth client id from a third-party app.
// That is client impersonation, and there is no public client
// registration for third-party apps. The sanctioned command is both
// safer and less code.
//
// Endpoint: GET https://api.anthropic.com/api/oauth/usage
//   { "five_hour":       { "utilization": 42, "resets_at": … },
//     "seven_day":       { "utilization": 18, "resets_at": … },
//     "seven_day_opus":  { "utilization":  5, "resets_at": … } }

import Foundation

struct ClaudeUsageSource: UsageSource {
    let provider = Provider.claude

    static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    let endpoint: URL
    /// Injectable so tests never touch the real keychain.
    let store: ClaudeTokenStore
    /// Injectable so tests never spawn a process.
    let authStatus: @Sendable () async -> ClaudeCLI.AuthStatus?
    let session: URLSession

    init(
        endpoint: URL = defaultEndpoint,
        store: ClaudeTokenStore = .keychain,
        authStatus: @escaping @Sendable () async -> ClaudeCLI.AuthStatus? = {
            await ClaudeCLI.authStatus()
        },
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.store = store
        self.authStatus = authStatus
        self.session = session
    }

    func fetch(now: Date) async -> ProviderState {
        guard let bundle = store.load() else { return await unconfiguredState() }

        // Refuse to spend a doomed call. An inference-only token (no
        // user:profile) CANNOT read usage — the endpoint requires that
        // scope — so surface a re-auth prompt without ever contacting the
        // rate-limited endpoint. This is a direct guard against the exact
        // failure that started this whole saga.
        guard bundle.canReadUsage else {
            Log.providers.notice("claude token lacks user:profile — sign-in required")
            return .failed(
                reason: "Sign in again — this token can't read usage",
                retry: .userAction
            )
        }

        // Refresh proactively: a call with an expired token would 401,
        // and refreshing hits the token endpoint, not the usage endpoint.
        let usable: ClaudeTokenBundle
        switch await refreshedIfNeeded(bundle, now: now) {
        case .success(let fresh): usable = fresh
        case .terminal(let reason): return .failed(reason: reason, retry: .userAction)
        case .transient(let reason): return .failed(reason: reason, retry: .after(5 * 60))
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(usable.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(reason: "Unexpected response from Anthropic", retry: .normal)
            }
            return handle(status: http.statusCode, data: data, http: http, now: now)
        } catch is CancellationError {
            return .failed(reason: "Cancelled", retry: .normal)
        } catch {
            // Deliberately not interpolating the error: URLError
            // descriptions can contain the full request URL.
            return .failed(reason: "Couldn't reach Anthropic", retry: .normal)
        }
    }

    /// Map an HTTP status to a provider state + retry policy. The retry
    /// policy is the load-bearing part: `.userAction` on auth failures is
    /// what stops the retry storm that IP-rate-limited this machine.
    private func handle(
        status: Int, data: Data, http: HTTPURLResponse, now: Date
    ) -> ProviderState {
        switch status {
        case 200:
            return decode(data, now: now)

        case 401, 403:
            // We already refreshed a valid-scope token, so this means
            // re-auth. NEVER auto-retry a rejected credential.
            let detail = apiErrorType(data).map { " (\($0))" } ?? ""
            let summary = "HTTP \(status)\(detail)"
            Log.providers.notice("claude usage auth rejected: \(summary, privacy: .public)")
            return .failed(reason: "Sign in again\(detail)", retry: .userAction)

        case 429:
            let pause = retryAfter(http) ?? RetryPolicy.defaultRateLimitPause
            Log.providers.notice("claude usage rate limited; pausing \(Int(pause), privacy: .public)s")
            return .failed(
                reason: "Rate limited by Anthropic — paused for \(Int(pause / 60))m",
                retry: .after(pause)
            )

        default:
            Log.providers.notice("claude usage HTTP \(status, privacy: .public)")
            return .failed(reason: "Anthropic returned HTTP \(status)", retry: .after(5 * 60))
        }
    }

    /// Anthropic errors are `{"error":{"type":…,"message":…}}`. The type
    /// is API metadata and safe to surface; the message can be verbose,
    /// so only the type is used.
    private func apiErrorType(_ data: Data) -> String? {
        struct Envelope: Decodable {
            struct APIError: Decodable { let type: String? }
            let error: APIError?
        }
        return try? JSONDecoder().decode(Envelope.self, from: data).error?.type
    }

    private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "retry-after"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return min(max(seconds, 60), 3600)
    }

    // MARK: - Refresh

    private enum TokenOutcome {
        case success(ClaudeTokenBundle)
        /// Dead refresh token — only a fresh sign-in fixes it.
        case terminal(String)
        /// A blip; try again later without forcing re-auth.
        case transient(String)
    }

    /// Refresh the token if it's expired or nearly so. Hits the token
    /// endpoint (platform.claude.com), never the usage endpoint, so this
    /// cannot contribute to a usage rate limit.
    private func refreshedIfNeeded(_ bundle: ClaudeTokenBundle, now: Date) async -> TokenOutcome {
        guard bundle.isExpired(now: now) else { return .success(bundle) }
        guard let refreshToken = bundle.refreshToken else {
            return .terminal("Session expired — sign in again")
        }

        do {
            let refreshed = try await ClaudeOAuth.refresh(refreshToken: refreshToken, session: session)
            // Some servers omit a new refresh token; keep the old one.
            let carried = ClaudeTokenBundle(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? bundle.refreshToken,
                expiresAt: refreshed.expiresAt,
                scopes: refreshed.scopes.isEmpty ? bundle.scopes : refreshed.scopes
            )
            store.save(carried)
            Log.providers.notice("claude token refreshed")
            return .success(carried)
        } catch ClaudeOAuthError.invalidGrant {
            return .terminal("Session expired — sign in again")
        } catch {
            return .transient("Couldn't refresh the Claude session")
        }
    }

    // MARK: - States

    /// No token yet. Distinguish "Claude Code isn't here at all" from
    /// "signed into Claude Code but Robut has no token of its own", so the
    /// UI can offer sign-in only when it makes sense.
    private func unconfiguredState() async -> ProviderState {
        guard ClaudeCLI.isInstalled else { return .notConfigured }
        guard let status = await authStatus(), status.loggedIn else {
            return .notConfigured
        }
        return .failed(reason: "Sign in to show Claude usage", retry: .userAction)
    }

    // MARK: - Decoding

    private func decode(_ data: Data, now: Date) -> ProviderState {
        guard let payload = try? JSONDecoder().decode(UsagePayload.self, from: data) else {
            // Shape only — never the body, which is account data.
            let keys = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?.keys.sorted().joined(separator: ",") } ?? "unparseable"
            Log.providers.notice("claude usage decode failed; keys=[\(keys, privacy: .public)]")
            return .failed(reason: "Couldn't read Anthropic's usage response", retry: .after(10 * 60))
        }

        let windows = payload.windows(provider: provider, now: now)
        guard !windows.isEmpty else {
            return .failed(reason: "Anthropic reported no usage windows", retry: .after(10 * 60))
        }

        return .ready(UsageSnapshot(
            provider: provider,
            windows: windows.sorted { $0.kind.order < $1.kind.order },
            sampledAt: now,
            planLabel: nil
        ))
    }
}
