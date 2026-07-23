// PaceEngine+LongHorizon.swift — forgiveness for windows longer than a day.
//
// Projecting a week from the last 90 minutes assumes you never sleep; that
// is how a 7%-used weekly once showed "runs dry ~1d 20h early". Windows
// with 24h+ to reset are instead projected from the LIVED rate (nights and
// idle days in the denominator — PacePattern), tempered by what completed
// past windows actually peaked at, and barred from crying red without at
// least one full day-night cycle of evidence.

import Foundation

extension PaceEngine {

    // MARK: - Long-horizon tuning

    /// At or beyond this time-to-reset, project from lived history.
    static let longHorizon: TimeInterval = 24 * 3600

    /// Lived-rate basis: as long as the horizon, within these bounds. The
    /// floor guarantees a day-night cycle; the cap keeps it current.
    static let livedLookbackCap: TimeInterval = 72 * 3600

    /// A shortfall claim about days requires at least a full lived day of
    /// evidence. Below this, project — but never red.
    static let representativeSpan: TimeInterval = 24 * 3600

    /// With thin evidence, being this far ahead of the even-pace marker is
    /// worth a gold nudge; anything less is still "measuring".
    static let evenPaceMargin = 0.10

    /// Prior-epoch tempering: weight grows with completed epochs seen,
    /// gets a boost while lived evidence is thin, and never dominates.
    static let priorWeightPerEpoch = 0.2
    static let priorWeightThinBoost = 0.2
    static let priorWeightCap = 0.5
    static let thinPriorSpan: TimeInterval = 48 * 3600

    // MARK: - Verdict

    /// The long-window sibling of `project(burn:window:now:safePerHour:)`.
    static func longHorizonVerdict(
        window: UsageWindow, samples: [UsageSample], now: Date, safePerHour: Double
    ) -> PaceVerdict {
        let remaining = window.remainingFraction
        let secondsToReset = window.resetsAt.timeIntervalSince(now)
        let hoursToReset = secondsToReset / 3600

        // The fetch we just did is itself an observation (see verdict()).
        var observed = samples
        if observed.last?.at != now {
            observed.append(UsageSample(at: now, usedFraction: window.usedFraction))
        }
        let lookback = min(livedLookbackCap, max(longHorizon, secondsToReset))
        let lived = PacePattern.livedRate(samples: observed, now: now, lookback: lookback)

        guard lived.confidence != .insufficient else {
            return PaceVerdict(
                outlook: .unknown, burnPerHour: nil, safePerHour: safePerHour, paceRatio: nil,
                projectedExhaustion: nil, shortfall: nil, headroomAtReset: nil
            )
        }
        guard lived.perHour > idleThreshold else {
            return PaceVerdict(
                outlook: .idle, burnPerHour: lived.perHour, safePerHour: safePerHour,
                paceRatio: 0, projectedExhaustion: nil, shortfall: nil, headroomAtReset: remaining
            )
        }

        return projectLived(
            lived: lived, window: window, samples: samples, now: now, safePerHour: safePerHour
        )
    }

    /// Where the lived pace lands at reset, tempered by how past windows
    /// actually ended (how much this human leaves on the table), with
    /// alarm severity gated on evidence.
    private static func projectLived(
        lived: BurnRate, window: UsageWindow, samples: [UsageSample], now: Date, safePerHour: Double
    ) -> PaceVerdict {
        let remaining = window.remainingFraction
        let hoursToReset = window.resetsAt.timeIntervalSince(now) / 3600

        let projected = window.usedFraction + lived.perHour * hoursToReset
        var expected = projected
        let peaks = PacePattern.priorEpochPeaks(samples: samples, now: now)
        if let heaviest = peaks.max() {
            let thin = lived.observedSpan < thinPriorSpan
            let weight = min(
                priorWeightCap,
                priorWeightPerEpoch * Double(peaks.count) + (thin ? priorWeightThinBoost : 0)
            )
            expected = max(window.usedFraction, (1 - weight) * projected + weight * heaviest)
        }
        let ratio = lived.perHour / safePerHour

        if expected < 1 {
            let effectiveRate = (expected - window.usedFraction) / hoursToReset
            let exhaustion = effectiveRate > idleThreshold
                ? now.addingTimeInterval((remaining / effectiveRate) * 3600)
                : nil
            let effectiveRatio = (expected - window.usedFraction) / remaining
            return PaceVerdict(
                outlook: effectiveRatio <= comfortableRatio ? .comfortable : .tight,
                burnPerHour: lived.perHour, safePerHour: safePerHour, paceRatio: ratio,
                projectedExhaustion: exhaustion, shortfall: nil,
                headroomAtReset: max(0, 1 - expected)
            )
        }

        // Projected over — but a red claim about unobserved days needs a
        // full lived cycle behind it. Thinner evidence: a gold nudge if
        // measurably ahead of the even-pace marker, else keep measuring.
        guard lived.observedSpan >= representativeSpan else {
            let ahead = window.usedFraction > window.elapsedFraction(now: now) + evenPaceMargin
            return PaceVerdict(
                outlook: ahead ? .tight : .unknown,
                burnPerHour: lived.perHour, safePerHour: safePerHour, paceRatio: ratio,
                projectedExhaustion: nil, shortfall: nil,
                headroomAtReset: ahead ? 0 : nil
            )
        }

        let effectiveRate = (expected - window.usedFraction) / hoursToReset
        let exhaustion = now.addingTimeInterval((remaining / effectiveRate) * 3600)
        return PaceVerdict(
            outlook: .shortfall, burnPerHour: lived.perHour, safePerHour: safePerHour,
            paceRatio: ratio, projectedExhaustion: exhaustion,
            shortfall: window.resetsAt.timeIntervalSince(exhaustion), headroomAtReset: 0
        )
    }
}
