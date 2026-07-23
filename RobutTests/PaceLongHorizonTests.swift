// PaceLongHorizonTests.swift — forgiveness for windows longer than a day.
//
// The scenarios that made Robut cry wolf: a hot morning extrapolated across
// a week of assumed non-stop usage. Lived-rate projection, evidence gating,
// and prior-week learning are pinned here. Verdict basics stay in
// PaceVerdictTests.swift.

import Foundation
import Testing

@testable import Robut

@Suite("Long-horizon forgiveness")
struct LongHorizonTests {

    /// A stretch of history: `burned` fraction consumed evenly across the
    /// active hours of each day, flat overnight — a human rhythm.
    private func dayNight(
        from start: Double, endingAt end: TimeInterval, days: Int, burnedPerDay: Double
    ) -> [UsageSample] {
        var out: [UsageSample] = []
        var level = start
        for day in (0..<days).reversed() {
            let dayEnd = end - Double(day) * 24 * 3600
            // Four readings across a 12h active stretch, then quiet.
            for step in 0...3 {
                let at = dayEnd - (12 - Double(step) * 4) * 3600
                level += step == 0 ? 0 : burnedPerDay / 3
                out.append(UsageSample(at: t0.addingTimeInterval(at), usedFraction: level))
            }
        }
        return out
    }

    @Test("THE bug: a hot morning must not red-flag a barely-touched week")
    func hotMorningDoesNotAlarmTheWeek() {
        // Live repro (2026-07-23): weekly at 7% used, ~158h to reset,
        // active all morning. The old engine extrapolated the 90-minute
        // active slope across 6.6 days of assumed non-stop usage → red.
        // With days of lived history (including nights), the honest
        // projection lands nowhere near 100%.
        let window = makeWindow(used: 0.07, resetsInHours: 158, lengthHours: 168, kind: .weekly)
        // Prior epoch: two modest days, ending in the reset 10h ago.
        var samples = dayNight(from: 0.55, endingAt: -12 * 3600, days: 2, burnedPerDay: 0.08)
        // Current epoch: sleep after the reset, then this morning's burn.
        samples += [
            UsageSample(at: t0.addingTimeInterval(-10 * 3600), usedFraction: 0.0),
            UsageSample(at: t0.addingTimeInterval(-4 * 3600), usedFraction: 0.01),
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.04),
            UsageSample(at: t0, usedFraction: 0.07),
        ]
        let verdict = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(verdict.outlook == .comfortable)
        #expect(verdict.outlook != .shortfall)
    }

    @Test("A fresh install can't know a week; it says so instead of crying wolf")
    func thinEvidenceIsMeasuringNotRed() {
        // Only 9 hours of history exist, all of it active. Projecting six
        // days from that would be a guess — the honest verdict is that
        // we're still measuring, not that the sky is falling.
        let window = makeWindow(used: 0.07, resetsInHours: 158, lengthHours: 168, kind: .weekly)
        let samples = rampSamples(from: 0, to: 0.07, hours: 9)
        let verdict = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(verdict.outlook == .unknown)
        #expect(verdict.outlook != .shortfall)
    }

    @Test("A thin-evidence HOT streak nudges tight, not red")
    func thinEvidenceHotStreakIsTight() {
        // 30% of the week gone within its first 10 hours — well ahead of
        // the pace marker. Worth a gold nudge, but still not a red claim
        // about five unobserved days.
        let window = makeWindow(used: 0.30, resetsInHours: 158, lengthHours: 168, kind: .weekly)
        let samples = rampSamples(from: 0, to: 0.30, hours: 9)
        let verdict = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(verdict.outlook == .tight)
    }

    @Test("Sustained multi-day overburn still goes red")
    func sustainedOverburnStaysRed() {
        // 80% gone in under three days with days still to go — the lived
        // rate itself (nights included) can't fit in what's left.
        // Forgiveness must never mute a true alarm.
        let window = makeWindow(used: 0.80, resetsInHours: 100, lengthHours: 168, kind: .weekly)
        var samples = dayNight(from: 0.0, endingAt: -4 * 3600, days: 3, burnedPerDay: 0.25)
        samples.append(UsageSample(at: t0, usedFraction: 0.80))
        let verdict = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(verdict.outlook == .shortfall)
        #expect((verdict.shortfall ?? 0) > 0)
    }

    @Test("Weeks that always leave quota on the table temper the projection")
    func priorWeeksTemper() {
        // Two completed weeks peaked around half. A hot start to this week
        // projects over 100% on lived rate alone, but the learned pattern
        // says these weeks just don't end that way — soften to gold.
        let window = makeWindow(used: 0.12, resetsInHours: 120, lengthHours: 168, kind: .weekly)
        // Two cleanly separated completed epochs, then the current one —
        // each starts after the previous ends so the drops are real resets.
        var samples = dayNight(from: 0, endingAt: -96 * 3600, days: 2, burnedPerDay: 0.25)
        samples += dayNight(from: 0, endingAt: -48 * 3600, days: 2, burnedPerDay: 0.275)
        // Current epoch: two lived days burning hard (nights included).
        samples += dayNight(from: 0.0, endingAt: -2 * 3600, days: 2, burnedPerDay: 0.055)
        samples.append(UsageSample(at: t0, usedFraction: 0.12))
        let verdict = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(verdict.outlook != .shortfall)
    }

    @Test("Sessions keep their fast reflexes")
    func sessionsStaySharp() {
        // Short horizons are activity-scale: extrapolating the last hour
        // across the next three is exactly right. Forgiveness is for
        // windows long enough to contain sleep.
        // 0.20/hr against 0.50 remaining empties in 2.5h; reset is 3h out.
        let window = makeWindow(used: 0.50, resetsInHours: 3, lengthHours: 5, kind: .session)
        let verdict = PaceEngine.verdict(
            window: window,
            samples: rampSamples(from: 0.30, to: 0.50, hours: 1),
            now: t0
        )
        #expect(verdict.outlook == .shortfall)
    }
}
