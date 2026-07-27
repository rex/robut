// PaceProjectionTests.swift — where the meter's marker lands.
//
// The marker replaced the pane's tinted prose, so its position IS the
// verdict now. Surplus and shortfall read off different axes on purpose
// (see PaceProjection) — these pin both, and the rule that the gap to the
// right edge is always the margin.

import Foundation
import Testing

@testable import Robut

@Suite("Projection marker")
struct PaceProjectionTests {

    private func verdict(
        _ outlook: PaceOutlook,
        exhaustion: Date? = nil,
        headroom: Double? = nil
    ) -> PaceVerdict {
        PaceVerdict(
            outlook: outlook, burnPerHour: 0.1, safePerHour: 0.1, paceRatio: 1,
            projectedExhaustion: exhaustion, shortfall: nil, headroomAtReset: headroom
        )
    }

    @Test("Surplus sits at the projected final usage")
    func surplusMeasuresBackFromTheEnd() {
        // 25% left over at reset → the marker sits at 75%, so the quarter
        // of the bar to its right is the quota left on the table.
        let window = makeWindow(used: 0.40, resetsInHours: 100)
        let projection = PaceProjection.of(
            verdict(.comfortable, headroom: 0.25), window: window, now: t0
        )
        #expect(projection?.kind == .surplus)
        #expect(abs((projection?.position ?? 0) - 0.75) < 1e-9)
    }

    @Test("Shortfall sits where you hit zero in the window's timeline")
    func shortfallMarksTheMoment() {
        // A 100-hour window, 25 hours elapsed, running dry 25 hours from
        // now: that's the halfway point of the window.
        let window = makeWindow(used: 0.60, resetsInHours: 75, lengthHours: 100)
        let projection = PaceProjection.of(
            verdict(.shortfall, exhaustion: t0.addingTimeInterval(25 * 3600)),
            window: window, now: t0
        )
        #expect(projection?.kind == .shortfall)
        #expect(abs((projection?.position ?? 0) - 0.50) < 1e-9)
    }

    @Test("An exhaustion at or past the reset is a surplus, not a shortfall")
    func exhaustionBeyondResetIsNotAShortfall() {
        // `.comfortable` still carries a projected-exhaustion date; it just
        // falls after the reset. That must not be read as running dry.
        let window = makeWindow(used: 0.40, resetsInHours: 100)
        let projection = PaceProjection.of(
            verdict(.comfortable, exhaustion: t0.addingTimeInterval(200 * 3600), headroom: 0.30),
            window: window, now: t0
        )
        #expect(projection?.kind == .surplus)
        #expect(abs((projection?.position ?? 0) - 0.70) < 1e-9)
    }

    @Test("Idle marks where usage stops climbing — right at the fill")
    func idleMarksTheFillEdge() {
        let window = makeWindow(used: 0.18, resetsInHours: 100)
        let projection = PaceProjection.of(
            verdict(.idle, headroom: 0.82), window: window, now: t0
        )
        #expect(abs((projection?.position ?? 0) - 0.18) < 1e-9)
    }

    @Test("Nothing to draw when we don't know, or there's nothing left")
    func silentStatesDrawNoMarker() {
        let window = makeWindow(used: 0.40, resetsInHours: 100)
        #expect(PaceProjection.of(nil, window: window, now: t0) == nil)
        #expect(PaceProjection.of(verdict(.unknown), window: window, now: t0) == nil)
        #expect(PaceProjection.of(verdict(.exhausted), window: window, now: t0) == nil)
        // Comfortable but with no headroom recorded: nothing honest to place.
        #expect(PaceProjection.of(verdict(.comfortable), window: window, now: t0) == nil)
    }

    @Test("Positions stay on the bar")
    func positionsAreClamped() {
        let window = makeWindow(used: 0.40, resetsInHours: 100)
        let over = PaceProjection.of(verdict(.idle, headroom: 1.4), window: window, now: t0)
        #expect((over?.position ?? -1) >= 0)
        let under = PaceProjection.of(verdict(.idle, headroom: -0.4), window: window, now: t0)
        #expect((under?.position ?? 2) <= 1)
    }

    @Test("End to end: a real verdict produces a placeable marker")
    func endToEndFromTheEngine() {
        let window = makeWindow(used: 0.20, resetsInHours: 100, lengthHours: 168)
        let result = PaceEngine.verdict(
            window: window, samples: rampSamples(from: 0.16, to: 0.20, hours: 30), now: t0
        )
        let projection = PaceProjection.of(result, window: window, now: t0)
        let position = try? #require(projection?.position)
        #expect((position ?? -1) >= 0 && (position ?? 2) <= 1)
    }
}
