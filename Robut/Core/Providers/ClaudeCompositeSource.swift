// ClaudeCompositeSource.swift — API first, CLI as fallback and as the
// insights carrier.
//
// Arbitration (unchanged from the original composite, ADR-0001): the
// fallback fires ONLY when the token path structurally cannot work — no
// token, or one the server rejected. It deliberately does NOT fire on a
// rate limit or a server error: those mean "ask again later", and
// spawning a CLI that hits the very same endpoint would just be a second
// way to make the problem worse.
//
// NEW: the analytics block ("insights") exists only in the CLI's text
// output. When the API path is serving, the CLI still runs on a slow
// cadence purely so its raw text reaches the stats ledger; its windows
// are discarded (the API's floats are strictly better).

import Foundation

struct ClaudeCompositeSource: UsageSource {
    let provider = Provider.claude

    /// How often the CLI rides along for insights while the API serves.
    static let insightsInterval: TimeInterval = 60 * 60

    let token: any UsageSource
    let cli: any UsageSource
    private let insightsClock = IntervalClock()

    init(token: any UsageSource, cli: any UsageSource) {
        self.token = token
        self.cli = cli
    }

    func fetch(now: Date) async -> ProviderState {
        let primary = await token.fetch(now: now)

        if case .ready = primary {
            // Served by the API. Let the CLI forward its text to the
            // stats ledger hourly; its windows are ignored.
            if await insightsClock.shouldFire(now: now, interval: Self.insightsInterval) {
                _ = await cli.fetch(now: now)
            }
            return primary
        }

        guard shouldFallBack(from: primary) else { return primary }

        // The token path can't serve, so the CLI is the operative path.
        let fallback = await cli.fetch(now: now)
        switch fallback {
        case .ready:
            Log.providers.notice("claude: token path unavailable, served by CLI")
            return fallback
        case .notConfigured:
            // No CLI to fall back to → show the token's guidance (sign in).
            return primary
        case .failed, .loading:
            // The CLI IS the working path (it needs no token), so surface
            // ITS state, not "sign in". A transient CLI failure then lets
            // the model keep the last-good data instead of nagging.
            return fallback
        }
    }

    func backfill() async -> [UsageSnapshot] {
        await cli.backfill()
    }

    private func shouldFallBack(from state: ProviderState) -> Bool {
        switch state {
        case .ready, .loading:
            false
        case .notConfigured:
            // Claude Code isn't even installed — nothing to fall back to.
            false
        case .failed(_, let retry):
            // Structural failures (sign-in needed) hand the job to the
            // CLI. Rate limits and server blips do not.
            retry == .userAction
        }
    }
}

/// A tiny actor throttle: fires at most once per interval. Lives here
/// because the composite is a struct and `fetch` is non-mutating.
actor IntervalClock {
    private var lastFired: Date?

    func shouldFire(now: Date, interval: TimeInterval) -> Bool {
        if let last = lastFired, now.timeIntervalSince(last) < interval {
            return false
        }
        lastFired = now
        return true
    }
}
