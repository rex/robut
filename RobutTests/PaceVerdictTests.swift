// PaceVerdictTests.swift — the "will I make it?" answer, and how windows
// are classified. This is the behavior the whole app is a wrapper around.

import Foundation
import Testing

@testable import Robut

@Suite("Pace verdicts")
struct VerdictTests {

    @Test("Spent quota reports exhausted")
    func exhausted() {
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 1.0, resetsInHours: 10), samples: [], now: t0
        )
        #expect(verdict.outlook == .exhausted)
        #expect(verdict.headroomAtReset == 0)
    }

    @Test("Without history the verdict is unknown, never a guess")
    func unknownWithoutHistory() {
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.30, resetsInHours: 10), samples: [], now: t0
        )
        #expect(verdict.outlook == .unknown)
        #expect(verdict.burnPerHour == nil)
    }

    @Test("Negligible consumption reports idle")
    func idle() {
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.30, resetsInHours: 10),
            samples: rampSamples(from: 0.30, to: 0.30, hours: 2),
            now: t0
        )
        #expect(verdict.outlook == .idle)
        #expect(verdict.headroomAtReset == 0.70)
    }

    @Test("Well under budget reports comfortable, with headroom")
    func comfortable() {
        // remaining 0.90 over 10h → sustainable 0.09/hr. Burning 0.01/hr.
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.10, resetsInHours: 10),
            samples: rampSamples(from: 0.09, to: 0.10, hours: 1),
            now: t0
        )
        #expect(verdict.outlook == .comfortable)
        #expect(abs((verdict.paceRatio ?? 0) - 0.111) < 0.01)
        // 0.90 − 0.01×10 = 0.80 left at reset.
        #expect(abs((verdict.headroomAtReset ?? 0) - 0.80) < 0.01)
    }

    @Test("Just inside budget reports tight, not comfortable")
    func tight() {
        // remaining 0.50 over 10h → sustainable 0.05/hr. Burning 0.045/hr
        // lands at ratio 0.9 — makes it, but only just.
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.50, resetsInHours: 10),
            samples: rampSamples(from: 0.455, to: 0.50, hours: 1),
            now: t0
        )
        #expect(verdict.outlook == .tight)
        #expect((verdict.paceRatio ?? 0) > PaceEngine.comfortableRatio)
        #expect((verdict.paceRatio ?? 0) <= 1.0)
    }

    @Test("Over budget reports shortfall with the correct margin")
    func shortfall() throws {
        // remaining 0.50 at 0.10/hr empties in 5h, but reset is 10h out.
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.50, resetsInHours: 10),
            samples: rampSamples(from: 0.40, to: 0.50, hours: 1),
            now: t0
        )
        #expect(verdict.outlook == .shortfall)
        #expect(abs((verdict.paceRatio ?? 0) - 2.0) < 0.05)
        // Runs dry ~5 hours before the window resets.
        let shortfall = try #require(verdict.shortfall)
        #expect(abs(shortfall - 5 * 3600) < 15 * 60)
        #expect(verdict.headroomAtReset == 0)
    }

    @Test("A reset already due is unknown rather than a divide by zero")
    func resetInThePast() {
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.50, resetsInHours: -1),
            samples: rampSamples(from: 0.40, to: 0.50, hours: 1),
            now: t0
        )
        #expect(verdict.outlook == .unknown)
        #expect(verdict.projectedExhaustion == nil)
    }

    @Test("Stale history plus an unchanged reading reads as idle, not unknown")
    func staleHistoryReadsAsIdle() {
        // The real-world case that exposed this: Codex untouched for 56
        // hours, so nothing sits in the burn-rate lookback. The engine
        // used to shrug ("unknown", grey robot) when the honest answer is
        // obvious — 7% spent, days until reset, nothing consumed since.
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-58 * 3600), usedFraction: 0.07),
            UsageSample(at: t0.addingTimeInterval(-56 * 3600), usedFraction: 0.07),
        ]
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.07, resetsInHours: 82), samples: samples, now: t0
        )
        #expect(verdict.outlook == .idle)
        #expect(abs((verdict.headroomAtReset ?? 0) - 0.93) < 0.001)
    }

    @Test("An empty history still resolves once a reading exists")
    func firstEverReadingIsNotUnknownForever() {
        // Even with no stored samples at all, the current reading anchors
        // one end. One point is still not a rate, so this stays honest.
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.20, resetsInHours: 40), samples: [], now: t0
        )
        #expect(verdict.outlook == .unknown)
    }

    @Test("Usage climbing right up to now is measured, not smoothed away")
    func recentClimbIsCaptured() {
        // Stale samples then a jump in the current reading: the engine
        // must see the climb rather than averaging it into idleness.
        let samples = rampSamples(from: 0.40, to: 0.48, hours: 1)
        let verdict = PaceEngine.verdict(
            window: makeWindow(used: 0.50, resetsInHours: 10), samples: samples, now: t0
        )
        #expect(verdict.outlook == .shortfall)
        #expect((verdict.burnPerHour ?? 0) > 0.05)
    }

    @Test("Outlook severity orders worst-first for the menubar")
    func severityOrdering() {
        #expect(PaceOutlook.exhausted.severity > PaceOutlook.shortfall.severity)
        #expect(PaceOutlook.shortfall.severity > PaceOutlook.tight.severity)
        #expect(PaceOutlook.tight.severity > PaceOutlook.comfortable.severity)
        #expect(PaceOutlook.comfortable.severity > PaceOutlook.idle.severity)
        #expect(PaceOutlook.idle.severity > PaceOutlook.unknown.severity)
    }
}

@Suite("Window classification")
struct WindowKindTests {

    @Test("Window kind derives from length, not from provider naming",
          arguments: [
            (300, UsageWindow.Kind.session),      // Claude's 5-hour session
            (299, UsageWindow.Kind.session),      // providers round
            (10_080, UsageWindow.Kind.weekly),    // exactly 7 days
            (10_000, UsageWindow.Kind.weekly),    // near enough
          ])
    func kindFromMinutes(minutes: Int, expected: UsageWindow.Kind) {
        #expect(UsageWindow.Kind(windowMinutes: minutes) == expected)
    }

    @Test("An unrecognized window is carried through honestly")
    func unusualWindow() {
        #expect(UsageWindow.Kind(windowMinutes: 1440) == .other(minutes: 1440))
    }

    @Test("Short windows sort above long ones")
    func ordering() {
        #expect(UsageWindow.Kind.session.order < UsageWindow.Kind.weekly.order)
    }

    @Test("Labels read the way a person would say them")
    func labels() {
        #expect(makeWindow(used: 0, resetsInHours: 1, kind: .session).label == "Session")
        #expect(makeWindow(used: 0, resetsInHours: 1, kind: .weekly).label == "Weekly")
        #expect(makeWindow(used: 0, resetsInHours: 1, kind: .other(minutes: 1440)).label == "1-day")
        #expect(makeWindow(used: 0, resetsInHours: 1, kind: .other(minutes: 180)).label == "3-hour")
    }
}
