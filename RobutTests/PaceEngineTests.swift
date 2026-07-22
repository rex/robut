// PaceEngineTests.swift — burn-rate estimation and window rollover.
//
// Verdict-level behavior lives in PaceVerdictTests.swift.

import Foundation
import Testing

@testable import Robut

@Suite("Burn rate estimation")
struct BurnRateTests {

    @Test("No samples yields insufficient confidence")
    func noSamples() {
        let rate = PaceEngine.burnRate(samples: [], now: t0)
        #expect(rate.confidence == .insufficient)
        #expect(rate.perHour == 0)
    }

    @Test("A single sample cannot establish a rate")
    func singleSample() {
        let rate = PaceEngine.burnRate(
            samples: [UsageSample(at: t0.addingTimeInterval(-600), usedFraction: 0.2)],
            now: t0
        )
        #expect(rate.confidence == .insufficient)
    }

    @Test("Samples spanning under five minutes are too thin to trust")
    func tooShortSpan() {
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-120), usedFraction: 0.10),
            UsageSample(at: t0, usedFraction: 0.14),
        ]
        #expect(PaceEngine.burnRate(samples: samples, now: t0).confidence == .insufficient)
    }

    @Test("Steady consumption recovers the true rate")
    func steadyBurn() {
        // 10% consumed over one hour → 0.10/hour.
        let rate = PaceEngine.burnRate(samples: rampSamples(from: 0, to: 0.10, hours: 1), now: t0)
        #expect(rate.confidence == .good)
        #expect(abs(rate.perHour - 0.10) < 0.001)
    }

    @Test("A short but real span reports low confidence, not insufficient")
    func lowConfidenceSpan() {
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-10 * 60), usedFraction: 0.10),
            UsageSample(at: t0, usedFraction: 0.12),
        ]
        let rate = PaceEngine.burnRate(samples: samples, now: t0)
        #expect(rate.confidence == .low)
        #expect(abs(rate.perHour - 0.12) < 0.01)
    }

    @Test("Flat usage reads as a zero rate, not a negative one")
    func flatUsage() {
        let rate = PaceEngine.burnRate(samples: rampSamples(from: 0.42, to: 0.42, hours: 2), now: t0)
        #expect(rate.perHour == 0)
    }

    @Test("Least squares resists a single spike near the end")
    func spikeResistance() {
        // Mostly flat, with one jump right before `now`. A naive
        // (last − first) ÷ elapsed fit would cry wolf here.
        var samples = rampSamples(from: 0.20, to: 0.21, hours: 2)
        samples.append(UsageSample(at: t0, usedFraction: 0.30))
        let rate = PaceEngine.burnRate(samples: samples, now: t0)
        // True end-to-end slope would be 0.05/hr; least squares stays well under.
        #expect(rate.perHour < 0.045)
    }

    @Test("Future samples are ignored")
    func futureSamplesIgnored() {
        var samples = rampSamples(from: 0, to: 0.10, hours: 1)
        samples.append(UsageSample(at: t0.addingTimeInterval(3600), usedFraction: 0.99))
        let rate = PaceEngine.burnRate(samples: samples, now: t0)
        #expect(abs(rate.perHour - 0.10) < 0.001)
    }
}

@Suite("Window rollover")
struct EpochTests {

    @Test("Samples before a reset are discarded")
    func dropsPreResetSamples() {
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-3 * 3600), usedFraction: 0.80),
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.90),
            // Reset happened here — usage drops.
            UsageSample(at: t0.addingTimeInterval(-1 * 3600), usedFraction: 0.05),
            UsageSample(at: t0, usedFraction: 0.10),
        ]
        let epoch = PaceEngine.samplesInCurrentEpoch(samples, now: t0, lookback: 6 * 3600)
        #expect(epoch.count == 2)
        #expect(epoch.first?.usedFraction == 0.05)
    }

    @Test("A fresh window reads as consuming, never as idle")
    func rolloverDoesNotReadAsIdle() {
        // Regressing across the reset boundary would give a large negative
        // slope, which clamps to zero and looks idle at exactly the moment
        // a new window starts being spent. It must not.
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-3 * 3600), usedFraction: 0.95),
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.05),
            UsageSample(at: t0.addingTimeInterval(-1 * 3600), usedFraction: 0.10),
            UsageSample(at: t0, usedFraction: 0.15),
        ]
        let rate = PaceEngine.burnRate(samples: samples, now: t0, lookback: 6 * 3600)
        #expect(rate.perHour > 0.04)
    }

    @Test("A slow poller still gets an estimate past the lookback")
    func keepsTailBeyondLookback() {
        // Both samples are older than the 90-minute lookback; rather than
        // reporting nothing, keep the last two so a sparse history works.
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-5 * 3600), usedFraction: 0.10),
            UsageSample(at: t0.addingTimeInterval(-4 * 3600), usedFraction: 0.20),
        ]
        let epoch = PaceEngine.samplesInCurrentEpoch(samples, now: t0)
        #expect(epoch.count == 2)
    }
}
