// TestSupport.swift — shared fixtures for the pace suites.
//
// Everything is synthetic and every case injects `now`, so no test here
// depends on the wall clock, the machine, or the person running it.
// PUBLIC REPO: never build fixtures from real provider files.

import Foundation

@testable import Robut

/// A fixed instant. Any date; the point is that it never moves.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Samples rising linearly from `from` to `to` across `hours`, one every
/// `everyMinutes`, with the last landing exactly on `endingAt`.
func rampSamples(
    from: Double,
    to: Double,
    hours: Double,
    everyMinutes: Double = 10,
    endingAt now: Date = t0
) -> [UsageSample] {
    let count = max(1, Int((hours * 60) / everyMinutes))
    return (0...count).map { step in
        let progress = Double(step) / Double(count)
        return UsageSample(
            at: now.addingTimeInterval(-(hours * 3600) + progress * hours * 3600),
            usedFraction: from + (to - from) * progress
        )
    }
}

func makeWindow(
    used: Double,
    resetsInHours: Double,
    lengthHours: Double = 168,
    provider: Provider = .codex,
    kind: UsageWindow.Kind = .weekly
) -> UsageWindow {
    UsageWindow(
        provider: provider,
        kind: kind,
        usedFraction: used,
        resetsAt: t0.addingTimeInterval(resetsInHours * 3600),
        length: lengthHours * 3600
    )
}

/// A Claude token store that hands back a full-scope, unexpired bundle
/// (or nothing when `token` is nil). Never touches the real keychain.
func syntheticClaudeStore(
    token: String?, scopes: [String] = ["user:inference", "user:profile"]
) -> ClaudeTokenStore {
    ClaudeTokenStore(
        load: {
            token.map {
                ClaudeTokenBundle(
                    accessToken: $0, refreshToken: "synthetic-refresh",
                    expiresAt: t0.addingTimeInterval(3600), scopes: scopes
                )
            }
        },
        save: { _ in },
        clear: {}
    )
}
