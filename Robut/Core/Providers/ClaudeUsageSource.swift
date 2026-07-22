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
    let token: @Sendable () -> String?
    /// Injectable so tests never spawn a process.
    let authStatus: @Sendable () async -> ClaudeCLI.AuthStatus?
    let session: URLSession

    init(
        endpoint: URL = defaultEndpoint,
        token: @escaping @Sendable () -> String? = { RobutKeychain.read(.claudeToken) },
        authStatus: @escaping @Sendable () async -> ClaudeCLI.AuthStatus? = {
            await ClaudeCLI.authStatus()
        },
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.token = token
        self.authStatus = authStatus
        self.session = session
    }

    func fetch(now: Date) async -> ProviderState {
        guard let token = token() else { return await unconfiguredState() }

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(reason: "Unexpected response from Anthropic", retry: .normal)
            }

            switch http.statusCode {
            case 200:
                return decode(data, now: now)

            case 401, 403:
                // NEVER auto-retry: a rejected credential cannot fix
                // itself, and retrying on a timer is what got this
                // machine IP-rate-limited in the first place.
                let detail = apiErrorType(data).map { " (\($0))" } ?? ""
                let summary = "HTTP \(http.statusCode)\(detail)"
                Log.providers.notice("claude usage auth rejected: \(summary, privacy: .public)")
                return .failed(
                    reason: "Token rejected\(detail) — tap to set up again",
                    retry: .userAction
                )

            case 429:
                let pause = retryAfter(http) ?? RetryPolicy.defaultRateLimitPause
                Log.providers.notice(
                    "claude usage rate limited; pausing \(Int(pause), privacy: .public)s"
                )
                return .failed(
                    reason: "Rate limited by Anthropic — paused for \(Int(pause / 60))m",
                    retry: .after(pause)
                )

            default:
                Log.providers.notice(
                    "claude usage HTTP \(http.statusCode, privacy: .public)"
                )
                return .failed(
                    reason: "Anthropic returned HTTP \(http.statusCode)",
                    retry: .after(5 * 60)
                )
            }
        } catch is CancellationError {
            return .failed(reason: "Cancelled", retry: .normal)
        } catch {
            // Deliberately not interpolating the error: URLError
            // descriptions can contain the full request URL.
            return .failed(reason: "Couldn't reach Anthropic", retry: .normal)
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

    /// No token yet. Distinguish "Claude Code isn't here" from "it's here
    /// and just needs one command", because only one of those is
    /// something the user can act on.
    private func unconfiguredState() async -> ProviderState {
        guard ClaudeCLI.isInstalled else { return .notConfigured }
        guard let status = await authStatus(), status.loggedIn else {
            return .notConfigured
        }
        return .failed(reason: "Run `claude setup-token`, then add it in Robut", retry: .userAction)
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

// MARK: - Wire format

private struct UsagePayload: Decodable {
    let fiveHour: Limit?
    let sevenDay: Limit?
    let sevenDayOpus: Limit?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }

    func windows(provider: Provider, now: Date) -> [UsageWindow] {
        [
            fiveHour?.window(provider: provider, minutes: 300, variant: nil, now: now),
            sevenDay?.window(provider: provider, minutes: 10_080, variant: nil, now: now),
            sevenDayOpus?.window(provider: provider, minutes: 10_080, variant: "Opus", now: now),
        ].compactMap { $0 }
    }

    struct Limit: Decodable {
        let utilization: Double?
        let utilizationPercent: Double?
        let resetsAt: FlexibleDate?

        enum CodingKeys: String, CodingKey {
            case utilization
            case utilizationPercent = "utilization_percent"
            case resetsAt = "resets_at"
        }

        func window(
            provider: Provider, minutes: Int, variant: String?, now: Date
        ) -> UsageWindow? {
            guard let percent = utilization ?? utilizationPercent else { return nil }
            let length = TimeInterval(minutes * 60)
            return UsageWindow(
                provider: provider,
                kind: UsageWindow.Kind(windowMinutes: minutes),
                variant: variant,
                usedFraction: min(1, max(0, percent / 100)),
                resetsAt: resetsAt?.date ?? now.addingTimeInterval(length),
                length: length
            )
        }
    }
}

/// `resets_at` has appeared as both a unix timestamp and an ISO-8601
/// string across versions. Accept either rather than break on a change.
private struct FlexibleDate: Decodable {
    let date: Date

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds)
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = ISO8601.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format"
            )
        }
        date = parsed
    }
}
