// PacePatternTests.swift — the lived-rate estimator and prior-epoch learning.
//
// These primitives are what let a multi-day projection include sleep and
// idle weekends (the duty cycle) and what the engine "learns" from past
// weeks. All synthetic, all clock-injected.

import Foundation
import Testing

@testable import Robut

@Suite("Lived consumption rate")
struct LivedRateTests {

    @Test("Idle stretches count: the rate is consumption per wall-clock hour")
    func includesIdleTime() {
        // 10% burned Monday, nothing overnight, 15% burned Tuesday:
        // 25% over 34 wall hours ≈ 0.74%/hr — NOT the 1.25%/hr of the
        // active stretches alone. Sleep is in the denominator.
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-34 * 3600), usedFraction: 0.10),
            UsageSample(at: t0.addingTimeInterval(-22 * 3600), usedFraction: 0.20),
            UsageSample(at: t0.addingTimeInterval(-10 * 3600), usedFraction: 0.20),
            UsageSample(at: t0, usedFraction: 0.35),
        ]
        let rate = PacePattern.livedRate(samples: samples, now: t0, lookback: 72 * 3600)
        #expect(abs(rate.perHour - 0.25 / 34) < 0.0005)
        #expect(rate.confidence == .good)   // ≥ 24h of lived evidence
    }

    @Test("A reset inside the span doesn't poison the rate")
    func survivesReset() {
        // Climb to 90%, reset, climb again. The negative delta is not
        // consumption; the post-reset level is (it rose from zero).
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-30 * 3600), usedFraction: 0.80),
            UsageSample(at: t0.addingTimeInterval(-26 * 3600), usedFraction: 0.90),
            UsageSample(at: t0.addingTimeInterval(-20 * 3600), usedFraction: 0.05),
            UsageSample(at: t0, usedFraction: 0.15),
        ]
        let rate = PacePattern.livedRate(samples: samples, now: t0, lookback: 72 * 3600)
        // 0.10 (pre-reset) + 0.05 (reset gap, from zero) + 0.10 (since).
        #expect(abs(rate.perHour - 0.25 / 30) < 0.0005)
        #expect(rate.perHour > 0)
    }

    @Test("Thin evidence is honest about itself")
    func confidenceTiers() {
        let short = [
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.10),
            UsageSample(at: t0, usedFraction: 0.14),
        ]
        let day: TimeInterval = 72 * 3600
        #expect(PacePattern.livedRate(samples: short, now: t0, lookback: day).confidence == .low)
        #expect(PacePattern.livedRate(samples: [], now: t0, lookback: day).confidence == .insufficient)
        let single = [UsageSample(at: t0.addingTimeInterval(-3600), usedFraction: 0.10)]
        #expect(PacePattern.livedRate(samples: single, now: t0, lookback: day).confidence == .insufficient)
    }

    @Test("Samples beyond the lookback still rescue a sparse history")
    func sparseFallback() {
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-100 * 3600), usedFraction: 0.10),
            UsageSample(at: t0, usedFraction: 0.30),
        ]
        let rate = PacePattern.livedRate(samples: samples, now: t0, lookback: 72 * 3600)
        #expect(rate.confidence != .insufficient)
        #expect(abs(rate.perHour - 0.20 / 100) < 0.0005)
    }
}

@Suite("Prior epoch learning")
struct PriorEpochTests {

    /// A completed epoch: climbs to `peak` over `hours`, sampled hourly.
    private func epoch(endingAt end: Date, peak: Double, hours: Double = 24) -> [UsageSample] {
        stride(from: hours, through: 0, by: -1).map { hoursAgo in
            UsageSample(
                at: end.addingTimeInterval(-hoursAgo * 3600),
                usedFraction: peak * (1 - hoursAgo / hours)
            )
        }
    }

    @Test("Completed weeks report their peaks; the current week is excluded")
    func extractsPeaks() {
        var samples = epoch(endingAt: t0.addingTimeInterval(-8 * 24 * 3600), peak: 0.45)
        samples += epoch(endingAt: t0.addingTimeInterval(-1 * 24 * 3600), peak: 0.55)
        // Current epoch, still climbing — must not count as a "peak".
        samples += [
            UsageSample(at: t0.addingTimeInterval(-6 * 3600), usedFraction: 0.02),
            UsageSample(at: t0.addingTimeInterval(-3 * 3600), usedFraction: 0.05),
            UsageSample(at: t0, usedFraction: 0.08),
        ]
        let peaks = PacePattern.priorEpochPeaks(samples: samples, now: t0)
        #expect(peaks.count == 2)
        #expect(abs((peaks.first ?? 0) - 0.45) < 0.01)
        #expect(abs((peaks.last ?? 0) - 0.55) < 0.01)
    }

    @Test("A sliver of an epoch is not a lesson")
    func qualityGate() {
        // Two samples over 20 minutes then a reset: too thin to describe
        // a week; must be dropped rather than recorded as a 3% "peak".
        var samples = [
            UsageSample(at: t0.addingTimeInterval(-50 * 3600), usedFraction: 0.02),
            UsageSample(at: t0.addingTimeInterval(-50 * 3600 + 1200), usedFraction: 0.03),
        ]
        samples += [
            UsageSample(at: t0.addingTimeInterval(-3600), usedFraction: 0.01),
            UsageSample(at: t0, usedFraction: 0.02),
        ]
        #expect(PacePattern.priorEpochPeaks(samples: samples, now: t0).isEmpty)
    }
}
