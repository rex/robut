// CodexUsageSource.swift — Codex usage with zero credentials.
//
// Codex writes its own rate-limit state to disk: every `token_count` event
// in a session rollout carries the `rate_limits` payload straight from the
// API response. So Robut just reads it. No token, no keychain, no network,
// and therefore nothing that can ever prompt.
//
// Layout:  ~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ts>-<uuid>.jsonl
// Each line is a JSON object; the ones that matter look like:
//
//   {"timestamp":"…","type":"event_msg","payload":{
//      "type":"token_count",
//      "rate_limits":{"primary":{"used_percent":7.0,
//                                "window_minutes":10080,
//                                "resets_at":1785045214},
//                     "secondary":null,"plan_type":"plus"}}}

import Foundation

struct CodexUsageSource: UsageSource {
    let provider = Provider.codex

    /// Injectable so tests run against synthetic fixtures. PUBLIC REPO:
    /// fixtures are always synthesized, never copied from a real machine.
    let sessionsRoot: URL

    /// How many recent rollout files to inspect. The newest file usually
    /// wins, but an idle session can leave a stale file on top, so look
    /// back a few and take the newest payload across them.
    let filesToScan: Int

    init(sessionsRoot: URL? = nil, filesToScan: Int = 5) {
        self.sessionsRoot = sessionsRoot
            ?? Self.homeDirectory().appending(path: ".codex/sessions", directoryHint: .isDirectory)
        self.filesToScan = filesToScan
    }

    func fetch(now: Date) async -> ProviderState {
        guard FileManager.default.fileExists(atPath: sessionsRoot.path(percentEncoded: false)) else {
            return .notConfigured
        }

        let files = recentRolloutFiles()
        guard !files.isEmpty else { return .notConfigured }

        var newest: (at: Date, limits: RateLimits)?
        for file in files {
            guard let found = lastRateLimits(in: file) else { continue }
            if let current = newest, found.at <= current.at { continue }
            newest = found
        }

        guard let newest else {
            return .failed(reason: "No usage data in recent Codex sessions yet")
        }

        let windows = newest.limits.windows(for: provider)
        guard !windows.isEmpty else {
            return .failed(reason: "Codex reported no rate-limit windows")
        }

        return .ready(UsageSnapshot(
            provider: provider,
            windows: windows.sorted { $0.kind.order < $1.kind.order },
            sampledAt: newest.at,
            planLabel: newest.limits.planType
        ))
    }

    // MARK: - File discovery

    /// Newest-first rollout files, capped at `filesToScan`.
    private func recentRolloutFiles() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var candidates: [(url: URL, modified: Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            candidates.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .prefix(filesToScan)
            .map(\.url)
    }

    /// Last `rate_limits` payload in a rollout file.
    ///
    /// Scans forward keeping the last match rather than reading backward:
    /// rollout files are modest, and a cheap `contains` check skips the
    /// ~99% of lines that are message content before any JSON parsing.
    private func lastRateLimits(in file: URL) -> (at: Date, limits: RateLimits)? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        let decoder = JSONDecoder()
        var result: (at: Date, limits: RateLimits)?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("rate_limits") else { continue }
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(RolloutEntry.self, from: data),
                  let limits = entry.payload?.rateLimits,
                  limits.hasAnyWindow
            else { continue }
            result = (entry.parsedTimestamp ?? Date.distantPast, limits)
        }
        return result
    }
}

// MARK: - Wire format

private struct RolloutEntry: Decodable {
    let timestamp: String?
    let payload: Payload?

    var parsedTimestamp: Date? {
        guard let timestamp else { return nil }
        return ISO8601.parse(timestamp)
    }

    struct Payload: Decodable {
        let rateLimits: RateLimits?
        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }
}

private struct RateLimits: Decodable {
    let primary: Window?
    let secondary: Window?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary, secondary
        case planType = "plan_type"
    }

    var hasAnyWindow: Bool { primary != nil || secondary != nil }

    func windows(for provider: Provider) -> [UsageWindow] {
        [primary, secondary].compactMap { $0?.asUsageWindow(provider: provider) }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        /// Unix seconds.
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        func asUsageWindow(provider: Provider) -> UsageWindow? {
            guard let windowMinutes, windowMinutes > 0 else { return nil }
            let length = TimeInterval(windowMinutes * 60)

            // resets_at is occasionally absent; fall back to a window
            // length from now so the row still renders honestly.
            let resets = resetsAt.map { Date(timeIntervalSince1970: $0) }
                ?? Date().addingTimeInterval(length)

            return UsageWindow(
                provider: provider,
                kind: UsageWindow.Kind(windowMinutes: windowMinutes),
                usedFraction: min(1, max(0, (usedPercent ?? 0) / 100)),
                resetsAt: resets,
                length: length
            )
        }
    }
}

/// ISO-8601 parsing that is safe to share across concurrency domains.
///
/// `ISO8601DateFormatter` is a non-Sendable class, so a shared static
/// instance is a Swift 6 error — and a genuine data race, not a
/// technicality. `Date.ISO8601FormatStyle` is a value type, so these
/// are free to be global.
enum ISO8601 {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    /// Codex writes fractional seconds; tolerate both shapes anyway.
    static func parse(_ string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }
}
