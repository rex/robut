// PaceEngine.swift — the heart of Robut.
//
// Everything else is plumbing to get numbers into this file and pixels out
// of it. The question it answers is the one the app exists for:
//
//     "At the rate I'm actually going, do I make it to the reset?"
//
// Pure and dependency-free by design — no Foundation date math beyond
// arithmetic, no I/O, no clock reads. `now` is always injected, which is
// what makes the whole thing exhaustively testable.

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

enum PaceEngine {

    // MARK: - Tuning

    /// Window of history used for the burn-rate fit. Long enough to smooth
    /// out a single heavy request, short enough to track "what I'm doing
    /// now" rather than "what I did this morning".
    static let defaultLookback: TimeInterval = 90 * 60

    /// Below this, treat as idle. 0.05%/hour would take 2000 hours to
    /// exhaust a quota — noise, not consumption.
    static let idleThreshold = 0.0005

    /// Minimum sample span before a fit means anything.
    static let minSpanForLow: TimeInterval = 5 * 60
    static let minSpanForGood: TimeInterval = 20 * 60

    /// Ratio below which you're comfortable rather than merely on-track.
    static let comfortableRatio = 0.85

    // MARK: - Burn rate

    /// Least-squares slope of usage over time, in fraction per hour.
    ///
    /// Least squares rather than (last − first) ÷ elapsed because usage
    /// arrives in lumps: a single big request right before you look would
    /// otherwise dominate the estimate and cry wolf.
    static func burnRate(
        samples: [UsageSample],
        now: Date,
        lookback: TimeInterval = defaultLookback
    ) -> BurnRate {
        let usable = samplesInCurrentEpoch(samples, now: now, lookback: lookback)

        guard usable.count >= 2,
              let first = usable.first,
              let last = usable.last
        else {
            return BurnRate(perHour: 0, confidence: .insufficient, observedSpan: 0)
        }

        let span = last.at.timeIntervalSince(first.at)
        guard span >= minSpanForLow else {
            return BurnRate(perHour: 0, confidence: .insufficient, observedSpan: span)
        }

        // Regress usedFraction on seconds-since-first.
        let count = Double(usable.count)
        let xs = usable.map { $0.at.timeIntervalSince(first.at) }
        let ys = usable.map(\.usedFraction)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }

        guard denominator > 0 else {
            return BurnRate(perHour: 0, confidence: .insufficient, observedSpan: span)
        }

        // Usage is monotonic within an epoch; a negative slope is noise.
        let perSecond = max(0, numerator / denominator)
        let confidence: BurnConfidence = span >= minSpanForGood ? .good : .low
        return BurnRate(perHour: perSecond * 3600, confidence: confidence, observedSpan: span)
    }

    /// Drop everything before the most recent reset, then apply the lookback.
    ///
    /// A window rollover shows up as usage *decreasing*. Regressing across
    /// that boundary would produce a large negative slope and read as
    /// "idle" at the exact moment a fresh window starts being consumed.
    static func samplesInCurrentEpoch(
        _ samples: [UsageSample],
        now: Date,
        lookback: TimeInterval = defaultLookback
    ) -> [UsageSample] {
        let ordered = samples.filter { $0.at <= now }.sorted { $0.at < $1.at }
        guard !ordered.isEmpty else { return [] }

        // Walk back from the end to the last point where usage dropped.
        var epochStart = ordered.startIndex
        for index in ordered.indices.dropFirst()
        where ordered[index].usedFraction < ordered[index - 1].usedFraction - 1e-9 {
            epochStart = index
        }

        let epoch = Array(ordered[epochStart...])
        let cutoff = now.addingTimeInterval(-lookback)
        let recent = epoch.filter { $0.at >= cutoff }

        // If the lookback cuts everything but the tail, keep the last two
        // in-epoch samples so a slow poller still produces an estimate.
        return recent.count >= 2 ? recent : Array(epoch.suffix(2))
    }

    // MARK: - Verdict

    /// The whole product, in one function.
    static func verdict(
        window: UsageWindow,
        samples: [UsageSample],
        now: Date,
        lookback: TimeInterval = defaultLookback
    ) -> PaceVerdict {
        let remaining = window.remainingFraction
        let secondsToReset = window.resetsAt.timeIntervalSince(now)

        // Already spent.
        guard remaining > 0 else {
            return PaceVerdict(
                outlook: .exhausted, burnPerHour: nil, safePerHour: 0, paceRatio: nil,
                projectedExhaustion: nil, shortfall: nil, headroomAtReset: 0
            )
        }

        // Reset is due (or the clock is off). Nothing to project onto.
        guard secondsToReset > 0 else {
            return PaceVerdict(
                outlook: .unknown, burnPerHour: nil, safePerHour: .infinity, paceRatio: nil,
                projectedExhaustion: nil, shortfall: nil, headroomAtReset: remaining
            )
        }

        let hoursToReset = secondsToReset / 3600
        let safePerHour = remaining / hoursToReset
        let burn = burnRate(samples: samples, now: now, lookback: lookback)

        guard burn.confidence != .insufficient else {
            return PaceVerdict(
                outlook: .unknown, burnPerHour: nil, safePerHour: safePerHour, paceRatio: nil,
                projectedExhaustion: nil, shortfall: nil, headroomAtReset: nil
            )
        }

        guard burn.perHour > idleThreshold else {
            return PaceVerdict(
                outlook: .idle, burnPerHour: burn.perHour, safePerHour: safePerHour,
                paceRatio: 0, projectedExhaustion: nil, shortfall: nil,
                headroomAtReset: remaining
            )
        }

        let ratio = burn.perHour / safePerHour
        let hoursToEmpty = remaining / burn.perHour
        let exhaustion = now.addingTimeInterval(hoursToEmpty * 3600)
        let headroom = remaining - burn.perHour * hoursToReset

        if exhaustion >= window.resetsAt {
            return PaceVerdict(
                outlook: ratio <= comfortableRatio ? .comfortable : .tight,
                burnPerHour: burn.perHour, safePerHour: safePerHour, paceRatio: ratio,
                projectedExhaustion: exhaustion, shortfall: nil,
                headroomAtReset: max(0, headroom)
            )
        }

        return PaceVerdict(
            outlook: .shortfall, burnPerHour: burn.perHour, safePerHour: safePerHour,
            paceRatio: ratio, projectedExhaustion: exhaustion,
            shortfall: window.resetsAt.timeIntervalSince(exhaustion),
            headroomAtReset: 0
        )
    }
}
