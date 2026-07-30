// ClaudeUsageWireTests.swift — decoding the /api/oauth/usage payload.
//
// Tests the Decodable shape directly (no network, no stub). PUBLIC REPO:
// payloads are synthetic. Field names are the ones read from the Claude
// Code binary.

import Foundation
import Testing

@testable import Robut

@Suite("Claude usage wire format")
struct ClaudeUsageWireTests {

    private func windows(_ json: String) throws -> [UsageWindow] {
        let payload = try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8))
        return payload.windows(provider: .claude, now: t0)
    }

    @Test("Every weekly variant the plan exposes is surfaced with its label")
    func allWeeklyVariants() throws {
        // CodexBar's "Weekly · Fable" is seven_day_overage_included — the
        // key an earlier version missed, so the row didn't appear at all.
        let ids = Set(try windows(#"""
        {"five_hour":{"utilization":0,"resets_at":1800005000},
         "seven_day":{"utilization":93,"resets_at":1800005000},
         "seven_day_opus":{"utilization":10,"resets_at":1800005000},
         "seven_day_sonnet":{"utilization":40,"resets_at":1800005000},
         "seven_day_overage_included":{"utilization":100,"resets_at":1800005000}}
        """#).map(\.id))

        #expect(ids.isSuperset(of: [
            "claude.session", "claude.weekly", "claude.weekly.Opus",
            "claude.weekly.Sonnet", "claude.weekly.Fable",
        ]))
    }

    @Test("The Fable weekly is labelled so a person recognizes it")
    func fableLabel() throws {
        let fable = try windows(
            #"{"seven_day_overage_included":{"utilization":100,"resets_at":1800005000}}"#
        ).first
        #expect(fable?.variant == "Fable")
        #expect(fable?.label.contains("Fable") == true)
    }

    @Test("A unix-timestamp resets_at is honoured, not the window-length fallback")
    func unixResetHonoured() throws {
        // resets_at 1800005000 is a real instant; the parsed reset must be
        // that, not now + 7 days. This is the bug the CLI-vs-CodexBar
        // comparison exposed: a fallback reset breaks the pace projection.
        let window = try #require(try windows(
            #"{"seven_day":{"utilization":50,"resets_at":1800005000}}"#
        ).first)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_800_005_000))
        #expect(window.resetsAt != t0.addingTimeInterval(window.length))
    }
}
