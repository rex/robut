// PaceTypes.swift — the value types the pace engine speaks in.
//
// Split out of PaceEngine.swift to keep that file focused on the maths
// (and under the architecture gate's line limit). No behaviour here.

import Foundation

/// A single observation of a window's usage.
struct UsageSample: Sendable, Hashable, Codable {
    let at: Date
    /// 0...1
    let usedFraction: Double
}

/// How much to trust a burn-rate estimate.
enum BurnConfidence: Sendable, Hashable {
    /// Not enough data (fewer than 2 samples, or too short a span).
    case insufficient
    /// Real but thin — a short span, so treat the projection as a hint.
    case low
    /// Enough spread to mean something.
    case good
}

/// Fraction-of-quota consumed per hour.
struct BurnRate: Sendable, Hashable {
    let perHour: Double
    let confidence: BurnConfidence
    /// Time between the first and last sample used for the fit.
    let observedSpan: TimeInterval
}

/// The verdict for one window.
enum PaceOutlook: Sendable, Hashable {
    /// Quota already spent.
    case exhausted
    /// Not enough history to say anything honest yet.
    case unknown
    /// Effectively no consumption — you'll obviously make it.
    case idle
    /// On pace with room to spare.
    case comfortable
    /// On pace to *just* make it. Small overrun and you won't.
    case tight
    /// Projected to run dry before the window resets.
    case shortfall

    /// Worst-first ordering, so the menubar can show the binding constraint.
    var severity: Int {
        switch self {
        case .exhausted: 5
        case .shortfall: 4
        case .tight: 3
        case .comfortable: 2
        case .idle: 1
        case .unknown: 0
        }
    }
}

struct PaceVerdict: Sendable, Hashable {
    let outlook: PaceOutlook
    /// nil when there isn't enough history.
    let burnPerHour: Double?
    /// The rate you could sustain and land exactly at empty on reset.
    let safePerHour: Double
    /// burn ÷ safe. 1.0 = exactly on budget, 2.0 = twice too fast.
    let paceRatio: Double?
    /// When you'd hit zero at the current rate. nil if never (or idle).
    let projectedExhaustion: Date?
    /// How long *before* the reset you run dry. Only set for `.shortfall`.
    let shortfall: TimeInterval?
    /// Fraction you'd still have at reset if you keep this pace.
    let headroomAtReset: Double?
}
