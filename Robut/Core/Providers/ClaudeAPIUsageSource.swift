// ClaudeAPIUsageSource.swift — Claude usage straight from the API.
//
// The primary Claude path (ADR-0001): one bounded GET against
// /api/oauth/usage with Robut's OWN full-scope token, returning float
// utilization and every window the plan exposes — where the CLI text
// rounds to integer percent (~81M tokens per step on a weekly) and
// succeeds ~2 of 3 times. The CLI remains the fallback and the insights
// carrier — see ClaudeCompositeSource.
//
// Token lifecycle lives ENTIRELY in ClaudeTokenManager (single-flight).
// This file maps HTTP outcomes to ProviderState; the retry policy is the
// load-bearing part: `.userAction` on auth failures is what stops the
// retry storm that once IP-rate-limited this machine.

import Foundation

struct ClaudeAPIUsageSource: UsageSource {
    let provider = Provider.claude

    static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    let endpoint: URL
    let manager: ClaudeTokenManager
    /// Injectable so tests never spawn a process.
    let authStatus: @Sendable () async -> ClaudeCLI.AuthStatus?
    let session: URLSession

    init(
        manager: ClaudeTokenManager,
        endpoint: URL = defaultEndpoint,
        authStatus: @escaping @Sendable () async -> ClaudeCLI.AuthStatus? = {
            await ClaudeCLI.authStatus()
        },
        session: URLSession = .robut
    ) {
        self.manager = manager
        self.endpoint = endpoint
        self.authStatus = authStatus
        self.session = session
    }

    func fetch(now: Date) async -> ProviderState {
        let usable: ClaudeTokenBundle
        switch await manager.validBundle(now: now) {
        case .noToken:
            return await unconfiguredState()
        case .signInRequired(let reason):
            return .failed(reason: reason, retry: .userAction)
        case .transient(let reason):
            return .failed(reason: reason, retry: .after(5 * 60))
        case .bundle(let bundle):
            usable = bundle
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

    /// The token path carries no history of its own; seeding stays with
    /// the composite's CLI side (which reads nothing anyway for Claude).
    func backfill() async -> [UsageSnapshot] { [] }

    // MARK: - Status mapping

    private func handle(
        status: Int, data: Data, http: HTTPURLResponse, now: Date
    ) -> ProviderState {
        switch status {
        case 200:
            return decode(data, now: now)

        case 401, 403:
            // The manager already refreshed a valid-scope token, so this
            // means re-auth. NEVER auto-retry a rejected credential.
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

    // MARK: - States

    /// No token yet. Distinguish "Claude Code isn't here at all" from
    /// "signed into Claude Code but Robut has no token of its own", so the
    /// composite can hand the CLI the job and the UI can offer sign-in.
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
