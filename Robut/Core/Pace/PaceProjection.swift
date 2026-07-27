// PaceProjection.swift — where the projected outcome lands on the meter.
//
// The meter's axis is quota (0 = untouched, 1 = spent), but under an even
// burn that axis doubles as the window's timeline — which is what lets one
// bar carry both readings. The two outcomes want different ones:
//
//   • SURPLUS — you finish with quota left. The interesting number is *how
//     much*, so the marker sits at the projected FINAL USAGE and the gap
//     to the right edge is the surplus you'll leave unused.
//
//   • SHORTFALL — you hit zero early. "How much" is degenerate (zero is
//     always the right edge), so the interesting number is *when*: the
//     marker sits where that moment falls in the window's timeline, and
//     the gap to the right edge is how long you'd be dry.
//
// Both read the same way — the gap at the right end is your margin — which
// is why one marker can serve both without a legend.

import Foundation

/// A projected outcome, positioned for drawing on a 0…1 meter.
struct PaceProjection: Sendable, Hashable {

    enum Kind: Sendable, Hashable {
        /// Projected to hit zero before the reset; `position` is when.
        case shortfall
        /// Projected to finish with room; `position` is the final usage.
        case surplus
    }

    /// 0…1 along the meter.
    let position: Double
    let kind: Kind

    /// Where `verdict` says this window lands, or nil when there's nothing
    /// honest to draw — we're still measuring, or the quota is already gone
    /// and the bar is full anyway.
    static func of(
        _ verdict: PaceVerdict?, window: UsageWindow, now: Date
    ) -> PaceProjection? {
        guard let verdict else { return nil }
        switch verdict.outlook {
        case .unknown, .exhausted:
            return nil
        case .comfortable, .idle, .tight, .shortfall:
            break
        }

        // Running dry inside the window: mark the moment it happens.
        if let exhaustion = verdict.projectedExhaustion, exhaustion < window.resetsAt {
            return PaceProjection(
                position: window.elapsedFraction(now: exhaustion), kind: .shortfall
            )
        }

        // Otherwise mark where usage is projected to stop climbing.
        guard let headroom = verdict.headroomAtReset else { return nil }
        return PaceProjection(
            position: max(0, min(1, 1 - headroom)), kind: .surplus
        )
    }
}
