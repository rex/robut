// PacePattern.swift — what the history says about how this human actually
// uses their allocation.
//
// The 90-minute slope answers "what am I doing right now" — the right basis
// for a 5-hour session, and a catastrophically wrong one for a week: it
// assumes the current burst continues 24/7, so a hot morning red-flags six
// days that will mostly be sleep and idle. These primitives measure the
// LIVED rate — consumption per wall-clock hour over days, nights included —
// and what completed past windows peaked at. Pure and clock-injected, like
// everything in Core/Pace.

import Foundation

enum PacePattern {

    /// Lived evidence spanning at least a full day-night cycle is solid.
    static let goodSpan: TimeInterval = 24 * 3600

    /// A prior epoch must be substantial before it counts as a lesson.
    static let minEpochSamples = 3
    static let minEpochSpan: TimeInterval = 12 * 3600

    /// Consumption per wall-clock hour: positive usage deltas divided by
    /// elapsed time, straight across reset boundaries. Idle stretches are
    /// in the denominator, which is the whole point — this is the rate at
    /// which the human consumes quota while living their life, not the
    /// rate at which they consume it while typing.
    static func livedRate(
        samples: [UsageSample], now: Date, lookback: TimeInterval
    ) -> BurnRate {
        let ordered = samples.filter { $0.at <= now }.sorted { $0.at < $1.at }
        let cutoff = now.addingTimeInterval(-lookback)
        let windowed = ordered.filter { $0.at >= cutoff }
        // A sparse history beyond the lookback still beats no answer.
        let usable = windowed.count >= 2 ? windowed : Array(ordered.suffix(2))

        guard usable.count >= 2, let first = usable.first, let last = usable.last else {
            return BurnRate(perHour: 0, confidence: .insufficient, observedSpan: 0)
        }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= PaceEngine.minSpanForLow else {
            return BurnRate(perHour: 0, confidence: .insufficient, observedSpan: span)
        }

        var consumed = 0.0
        for (previous, next) in zip(usable, usable.dropFirst()) {
            let delta = next.usedFraction - previous.usedFraction
            // A drop is a reset, not negative consumption; whatever the
            // level reached after it was climbed from zero.
            consumed += delta >= 0 ? delta : max(0, next.usedFraction)
        }

        let confidence: BurnConfidence = span >= goodSpan ? .good : .low
        return BurnRate(perHour: consumed / (span / 3600), confidence: confidence, observedSpan: span)
    }

    /// The peak usedFraction reached in each COMPLETED prior epoch — how
    /// much of past windows was actually consumed before they reset. The
    /// current, still-running epoch is excluded; slivers too thin to
    /// describe a window are dropped rather than recorded as tiny peaks.
    static func priorEpochPeaks(samples: [UsageSample], now: Date) -> [Double] {
        let ordered = samples.filter { $0.at <= now }.sorted { $0.at < $1.at }
        guard !ordered.isEmpty else { return [] }

        var epochs: [[UsageSample]] = [[]]
        var previous: UsageSample?
        for sample in ordered {
            if let last = previous, sample.usedFraction < last.usedFraction - 1e-9 {
                epochs.append([])
            }
            epochs[epochs.count - 1].append(sample)
            previous = sample
        }

        return epochs.dropLast().compactMap { epoch in
            guard epoch.count >= minEpochSamples,
                  let first = epoch.first, let last = epoch.last,
                  last.at.timeIntervalSince(first.at) >= minEpochSpan
            else { return nil }
            return epoch.map(\.usedFraction).max()
        }
    }
}
