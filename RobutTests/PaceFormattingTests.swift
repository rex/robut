// PaceFormattingTests.swift — the user-facing strings.

import Foundation
import Testing

@testable import Robut

@Suite("Pace formatting")
struct PaceFormattingTests {

    @Test("A session reset is a relative countdown, like the Claude Code app")
    func sessionRelative() {
        let window = makeWindow(used: 0.02, resetsInHours: 4.45, lengthHours: 5, kind: .session)
        let text = PaceFormatting.resetText(for: window, now: t0)
        #expect(text.hasPrefix("resets in "))
        #expect(text.contains("4h"))
    }

    @Test("A weekly reset is an absolute day + time, like the Claude Code app")
    func weeklyAbsolute() {
        // "resets in 6d 18h" is hard to act on; "resets Thu 3:00 AM" isn't.
        let window = makeWindow(used: 0.05, resetsInHours: 162, lengthHours: 168, kind: .weekly)
        let text = PaceFormatting.resetText(for: window, now: t0)
        #expect(text.hasPrefix("resets "))
        #expect(!text.contains(" in "))          // not the relative form
        #expect(text != "resets in 6d 18h")
    }

    @Test("A window already due says it's resetting")
    func due() {
        let window = makeWindow(used: 0.9, resetsInHours: -0.5, kind: .weekly)
        #expect(PaceFormatting.resetText(for: window, now: t0) == "resetting…")
    }

    @Test("Percent renders whole numbers, and distinguishes zero from nearly-zero")
    func percents() {
        #expect(PaceFormatting.percent(0.05) == "5%")
        #expect(PaceFormatting.percent(0) == "0%")
        #expect(PaceFormatting.percent(0.004) == "<1%")
    }
}
