// PaceAlarmTests.swift — how loudly Robut is allowed to shout.
//
// The outlook says what happens; the alarm says whether it costs you
// anything. These pin the difference, because collapsing the two is what
// made the menubar red roughly half the time — measured against real
// history, with gold never appearing at all.

import Foundation
import Testing

@testable import Robut

@Suite("Alarm level")
struct PaceAlarmTests {

    /// A verdict with only the fields `alarmLevel` reads.
    private func verdict(
        _ outlook: PaceOutlook, dryFor shortfall: TimeInterval? = nil
    ) -> PaceVerdict {
        PaceVerdict(
            outlook: outlook, burnPerHour: 0.1, safePerHour: 0.1, paceRatio: 1,
            projectedExhaustion: nil, shortfall: shortfall, headroomAtReset: nil
        )
    }

    private func level(
        _ outlook: PaceOutlook, dryFor: TimeInterval? = nil,
        resetsInHours: Double, lengthHours: Double = 168
    ) -> PaceAlarm {
        PaceEngine.alarmLevel(
            for: verdict(outlook, dryFor: dryFor),
            window: makeWindow(used: 0.5, resetsInHours: resetsInHours, lengthHours: lengthHours),
            now: t0
        )
    }

    @Test("Making it comfortably says nothing at all")
    func calmStatesAreSilent() {
        #expect(level(.comfortable, resetsInHours: 100) == PaceAlarm.none)
        #expect(level(.idle, resetsInHours: 100) == PaceAlarm.none)
        #expect(level(.unknown, resetsInHours: 100) == PaceAlarm.none)
    }

    @Test("Cutting it close is a notice, never an alert")
    func tightIsAlwaysGold() {
        #expect(level(.tight, resetsInHours: 2) == .notice)
        #expect(level(.tight, resetsInHours: 150) == .notice)
    }

    @Test("A session can NEVER raise a full alert")
    func sessionsCannotScream() {
        // The loudest a 5-hour window can be: spent, with the whole window
        // still to run. It still refills within hours, so it stays gold.
        // This is the single biggest source of the old constant red.
        #expect(level(.exhausted, resetsInHours: 4.9, lengthHours: 5) == .notice)
        #expect(level(.shortfall, dryFor: 4.5 * 3600, resetsInHours: 4.9, lengthHours: 5) == .notice)
        #expect(level(.shortfall, dryFor: 0.5 * 3600, resetsInHours: 3, lengthHours: 5) == .notice)
    }

    @Test("A blown WEEK is a real alert")
    func spentWeeklyAlerts() {
        // Two days of being blocked is exactly what red should mean.
        #expect(level(.exhausted, resetsInHours: 48) == .alert)
    }

    @Test("Running dry early only alarms once it costs a real share of what's left")
    func toleranceDecaysTowardTheReset() {
        // Typical live reading: dry ~20h early with five days still to go.
        // That's inside the projection's error bars and there is ample room
        // to self-correct — a notice, not an alarm.
        #expect(level(.shortfall, dryFor: 20 * 3600, resetsInHours: 120) == .notice)
        // The same claim with twelve hours left is neither uncertain nor
        // avoidable, so it earns the red it always should have had.
        #expect(level(.shortfall, dryFor: 8 * 3600, resetsInHours: 12) == .alert)
    }

    @Test("Being briefly dry right at the end is never worth red")
    func trivialDryStretchStaysGold() {
        #expect(level(.shortfall, dryFor: 2 * 3600, resetsInHours: 12) == .notice)
    }

    @Test("A true runaway still alarms")
    func runawayStillAlerts() {
        // Half a week gone in a day, six days to go. Forgiveness must never
        // reach this far — the counterpart to the engine's own overburn test.
        let window = makeWindow(used: 0.50, resetsInHours: 144, lengthHours: 168)
        let samples = rampSamples(from: 0, to: 0.50, hours: 24)
        let result = PaceEngine.verdict(window: window, samples: samples, now: t0)
        #expect(result.outlook == .shortfall)
        #expect(result.alarm == .alert)
    }

    @Test("The engine stamps an alarm on every verdict it hands out")
    func verdictAlwaysCarriesAnAlarm() {
        // A quiet week: reported, and reported as silent.
        let window = makeWindow(used: 0.05, resetsInHours: 150, lengthHours: 168)
        let result = PaceEngine.verdict(
            window: window, samples: rampSamples(from: 0.04, to: 0.05, hours: 30), now: t0
        )
        #expect(result.alarm == PaceAlarm.none)
    }
}

@Suite("Alarm-tempered mood")
struct RobotMoodAlarmTests {

    private func mood(_ outlook: PaceOutlook, _ alarm: PaceAlarm) -> RobotMood {
        var verdict = PaceVerdict(
            outlook: outlook, burnPerHour: nil, safePerHour: 0, paceRatio: nil,
            projectedExhaustion: nil, shortfall: nil, headroomAtReset: nil
        )
        verdict.alarm = alarm
        return RobotMood(verdict: verdict)
    }

    @Test("Colour follows the alarm, not the outlook")
    func colourTracksAlarm() {
        // The same factual outlook, two different volumes, two colours.
        #expect(mood(.shortfall, .alert) == .alarmed)
        #expect(mood(.shortfall, .notice) == .squint)
        #expect(mood(.exhausted, .notice) == .squint)
        #expect(mood(.exhausted, .alert) == .alarmed)
    }

    @Test("Calm and unknown are unaffected")
    func calmStaysCalm() {
        #expect(mood(.comfortable, .none) == .calm)
        #expect(mood(.idle, .none) == .calm)
        #expect(mood(.unknown, .none) == .dim)
        #expect(RobotMood(verdict: nil) == .dim)
    }

    @Test("Loudest wins when folding many windows into one icon")
    func rankOrdersLoudestLast() {
        #expect(RobotMood.dim.rank < RobotMood.calm.rank)
        #expect(RobotMood.calm.rank < RobotMood.squint.rank)
        #expect(RobotMood.squint.rank < RobotMood.alarmed.rank)
    }
}
