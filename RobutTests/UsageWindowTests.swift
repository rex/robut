// UsageWindowTests.swift — the window value type's pure geometry.
//
// elapsedFraction is what the pane draws as the "safe pace" marker, so it
// has to be right at the edges: 0 at the start, ~0.5 at the midpoint, and
// clamped to 1 once the window is due.

import Foundation
import Testing

@testable import Robut

@Suite("Usage window")
struct UsageWindowTests {

    @Test("Elapsed fraction is 0 at the very start of a window")
    func startOfWindow() {
        // Resets exactly one length from now → the window just began.
        let window = makeWindow(used: 0, resetsInHours: 5, lengthHours: 5, kind: .session)
        #expect(window.elapsedFraction(now: t0) == 0)
    }

    @Test("Elapsed fraction is ~0.5 at the midpoint")
    func midpoint() {
        let window = makeWindow(used: 0.4, resetsInHours: 2.5, lengthHours: 5, kind: .session)
        #expect(abs(window.elapsedFraction(now: t0) - 0.5) < 0.0001)
    }

    @Test("Elapsed fraction clamps to 1 once the window is due")
    func pastReset() {
        let window = makeWindow(used: 0.9, resetsInHours: -1, lengthHours: 5, kind: .session)
        #expect(window.elapsedFraction(now: t0) == 1)
    }

    @Test("A weekly window near its start reads just above 0")
    func weeklyStart() {
        let window = makeWindow(used: 0.05, resetsInHours: 162, lengthHours: 168, kind: .weekly)
        let elapsed = window.elapsedFraction(now: t0)
        #expect(elapsed > 0 && elapsed < 0.05)   // 6/168 ≈ 0.036
    }
}
