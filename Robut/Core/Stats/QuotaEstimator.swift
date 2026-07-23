// QuotaEstimator.swift — the tokens-per-percent correlation.
//
// Neither provider says how many tokens a window holds; Robut sees the
// PERCENT series (usage history) and, separately, the machine's actual
// token consumption per hour (transcript scans). Correlating the two —
// tokens consumed between two percent readings ÷ the percent moved —
// yields an estimate of "1% of this window ≈ N tokens", and from it the
// absolute size of the quota and the tokens left in the window.
//
// Honest by construction: local tokens are a floor (other machines and
// surfaces also consume the same account-wide percent), so the estimate
// is a LOWER bound that is accurate when this machine dominates. Median
// over many intervals resists the outliers that mismatch creates.

import Foundation

enum QuotaEstimator {

    /// A percent step smaller than this is noise, not signal.
    static let minPercentDelta = 1.0
    /// Pairs further apart than this blur too much activity together.
    static let maxIntervalSeconds: TimeInterval = 48 * 3600
    static let minPairs = 2

    static func estimate(
        windowID: String,
        samples: [UsageSample],
        hourlyTokens: [Int: TokenTally],
        now: Date
    ) -> QuotaEstimate? {
        let ordered = samples.filter { $0.at <= now }.sorted { $0.at < $1.at }
        guard ordered.count >= 2 else { return nil }

        var ratios: [Double] = []
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            let percentDelta = (next.usedFraction - previous.usedFraction) * 100
            let span = next.at.timeIntervalSince(previous.at)
            // Drops are resets; tiny moves are noise; long gaps are blur.
            guard percentDelta >= minPercentDelta, span > 0, span <= maxIntervalSeconds
            else { continue }

            let tokens = tokensBetween(previous.at, next.at, in: hourlyTokens)
            guard tokens > 0 else { continue }
            ratios.append(Double(tokens) / percentDelta)
        }
        guard ratios.count >= minPairs else { return nil }

        let sorted = ratios.sorted()
        let median = sorted[sorted.count / 2]
        return QuotaEstimate(
            windowID: windowID,
            tokensPerPercent: median,
            estimatedWindowTokens: median * 100,
            sampleCount: ratios.count,
            asOf: now
        )
    }

    /// Sum of hour buckets overlapping [from, to) — bucket-granular on
    /// purpose; the median across pairs absorbs the edge slop.
    static func tokensBetween(_ from: Date, _ to: Date, in hourly: [Int: TokenTally]) -> Int {
        let firstHour = StatsScanning.hourKey(from)
        let lastHour = StatsScanning.hourKey(to)
        var sum = 0
        var hour = firstHour
        while hour <= lastHour {
            sum += hourly[hour]?.total ?? 0
            hour += 3600
        }
        return sum
    }
}
