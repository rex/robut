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

        // A window more than a day out is projected from LIVED history —
        // nights and idle days included — not from the last 90 minutes.
        // Extrapolating an active-morning slope across a week assumes the
        // human never sleeps; see PaceEngine+LongHorizon.swift.
        if secondsToReset >= Self.longHorizon {
            return longHorizonVerdict(window: window, samples: samples, now: now, safePerHour: safePerHour)
        }

        // `now` is itself an observation: the fetch we just did reported
        // this window's current usage, so treat it as a sample.
        //
        // Without this, an idle machine reads as "unknown" forever. The
        // newest *stored* sample can be many hours old — providers only
        // log while you're using them — and sample-to-sample slope alone
        // cannot see the flat stretch between then and now. Anchoring at
        // `now` makes that stretch visible, which is what turns "no idea"
        // into the correct answer: you haven't used any, so you'll make it.
        var observed = samples
        if observed.last?.at != now {
            observed.append(UsageSample(at: now, usedFraction: window.usedFraction))
        }
        let burn = burnRate(samples: observed, now: now, lookback: lookback)

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

        return project(burn: burn, window: window, now: now, safePerHour: safePerHour)
    }

    /// Project a known, non-idle burn rate forward against the deadline.
    private static func project(
        burn: BurnRate,
        window: UsageWindow,
        now: Date,
        safePerHour: Double
    ) -> PaceVerdict {
        let remaining = window.remainingFraction
        let hoursToReset = window.resetsAt.timeIntervalSince(now) / 3600
        let ratio = burn.perHour / safePerHour
        let exhaustion = now.addingTimeInterval((remaining / burn.perHour) * 3600)
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
