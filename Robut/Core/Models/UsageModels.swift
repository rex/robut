// UsageModels.swift — the value types every provider normalizes into.
//
// Deliberately dumb: no I/O, no dates-from-now, no formatting. Providers
// produce these; the pace engine consumes them; the UI renders them.

import Foundation

/// A provider Robut tracks. v1 is intentionally two — scope restraint is
/// a feature, not an omission.
enum Provider: String, CaseIterable, Sendable, Identifiable, Codable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

/// One rate-limit window: "the weekly quota", "the 5-hour session quota".
///
/// Providers disagree about naming (Codex says primary/secondary, Claude
/// says session/weekly) and the same slot can change meaning between
/// releases. So `kind` is derived from the window's *length*, which is
/// the thing that actually stays stable.
struct UsageWindow: Sendable, Hashable, Identifiable, Codable {
    enum Kind: Sendable, Hashable, Codable {
        /// Short rolling window — Claude's 5-hour session, and friends.
        case session
        /// Seven-day window.
        case weekly
        /// Anything else, carried so we can still label it honestly.
        case other(minutes: Int)

        /// Derive from window length. Boundaries are generous because
        /// providers round (10080 min = exactly 7d, but 5h shows up as
        /// 300 and sometimes 299).
        init(windowMinutes: Int) {
            switch windowMinutes {
            case ..<1: self = .other(minutes: windowMinutes)
            case 1...(60 * 8): self = .session
            case (60 * 24 * 6)...(60 * 24 * 8): self = .weekly
            default: self = .other(minutes: windowMinutes)
            }
        }

        var slug: String {
            switch self {
            case .session: "session"
            case .weekly: "weekly"
            case .other(let minutes): "other-\(minutes)"
            }
        }

        /// Sort key so the pane lists short windows above long ones.
        var order: Int {
            switch self {
            case .session: 0
            case .other: 1
            case .weekly: 2
            }
        }
    }

    let provider: Provider
    let kind: Kind
    /// Distinguishes several windows of the SAME kind. Claude bills a
    /// general seven-day limit and a separate seven-day Opus limit; both
    /// are `.weekly`, so without this they'd collide on `id` and
    /// overwrite each other's history.
    let variant: String?
    /// 0...1. Providers report percent; normalize at the boundary.
    let usedFraction: Double
    let resetsAt: Date
    /// Full length of the window, used to compute how far into it we are.
    let length: TimeInterval

    init(
        provider: Provider,
        kind: Kind,
        variant: String? = nil,
        usedFraction: Double,
        resetsAt: Date,
        length: TimeInterval
    ) {
        self.provider = provider
        self.kind = kind
        self.variant = variant
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
        self.length = length
    }

    /// Stable across refreshes — this is the key history is bucketed by.
    var id: String {
        let base = "\(provider.rawValue).\(kind.slug)"
        return variant.map { "\(base).\($0)" } ?? base
    }

    var label: String {
        let base: String = switch kind {
        case .session: "Session"
        case .weekly: "Weekly"
        case .other(let minutes) where minutes % (60 * 24) == 0: "\(minutes / (60 * 24))-day"
        case .other(let minutes) where minutes % 60 == 0: "\(minutes / 60)-hour"
        case .other(let minutes): "\(minutes)-minute"
        }
        return variant.map { "\(base) · \($0)" } ?? base
    }

    var remainingFraction: Double { max(0, 1 - usedFraction) }

    /// When this window began, inferred from its reset time and length.
    var startedAt: Date { resetsAt.addingTimeInterval(-length) }
}

/// One provider's complete state at one moment.
struct UsageSnapshot: Sendable, Hashable, Identifiable, Codable {
    let provider: Provider
    let windows: [UsageWindow]
    let sampledAt: Date
    /// Plan name if the provider volunteers one ("plus", "max"). Display
    /// only — never used for logic, since the strings are not stable.
    let planLabel: String?

    var id: String { provider.rawValue }
}

/// What Robut knows about a provider right now, including the ways it can
/// fail. Failure is a first-class state: a provider that can't be read
/// shows a muted row and never interrupts the user.
enum ProviderState: Sendable {
    case loading
    case ready(UsageSnapshot)
    /// Provider isn't set up on this machine at all (no ~/.codex, not
    /// signed in). Not an error — just nothing to show.
    case notConfigured
    /// Configured but the read failed. Carries a short human reason and,
    /// crucially, whether retrying could ever help.
    case failed(reason: String, retry: RetryPolicy)

    var snapshot: UsageSnapshot? {
        if case .ready(let snapshot) = self { return snapshot }
        return nil
    }

    var retryPolicy: RetryPolicy {
        if case .failed(_, let retry) = self { return retry }
        return .normal
    }
}

/// When a failed provider may be polled again.
///
/// This exists because Robut once retried a rejected token on every tick
/// and got the machine IP-rate-limited by Anthropic. A failure that
/// cannot fix itself must not be retried on a timer — that's not
/// resilience, it's a denial-of-service against your own account.
enum RetryPolicy: Sendable, Hashable {
    /// Back off on the normal refresh interval.
    case normal
    /// Wait at least this long. Used for rate limits and server errors.
    case after(TimeInterval)
    /// Never automatically. Requires the user to change something —
    /// a rejected credential is the canonical case.
    case userAction

    /// Sensible pause for a rate limit when the server doesn't say.
    static let defaultRateLimitPause: TimeInterval = 15 * 60
}
