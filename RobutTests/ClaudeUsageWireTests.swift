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

    @Test("Model-scoped `limits` entries surface as weekly variants — today's Fable shape")
    func scopedLimitsSurface() throws {
        // Live finding (2026-07-30): the Fable weekly no longer arrives as
        // seven_day_overage_included; it comes ONLY via the `limits` array
        // (kind weekly_scoped + scope.model.display_name). Missing this is
        // exactly how the Fable row vanished from the pane.
        let result = try windows(#"""
        {"five_hour":{"utilization":18.37,"resets_at":1800005000},
         "seven_day":{"utilization":0.42,"resets_at":1800400000},
         "limits":[
           {"kind":"weekly_scoped","percent":12.4,"resets_at":1800400000,
            "scope":{"model":{"display_name":"Fable"}}},
           {"kind":"session_scoped","percent":5,"resets_at":1800005000,
            "scope":{"model":{"display_name":"Mystery"}}}]}
        """#)

        let ids = Set(result.map(\.id))
        // Continuity: the scoped Fable lands in the SAME history bucket
        // the CLI text produced. Unknown kinds are ignored, not errors.
        #expect(ids == ["claude.session", "claude.weekly", "claude.weekly.Fable"])

        let fable = try #require(result.first { $0.variant == "Fable" })
        #expect(abs(fable.usedFraction - 0.124) < 1e-9)
        // Floats survive — the whole point of the API path. The CLI text
        // would have shown these as 18% and 0%.
        let session = try #require(result.first { $0.kind == .session })
        #expect(abs(session.usedFraction - 0.1837) < 1e-9)
    }

    @Test("A scoped entry duplicating a legacy key does not corrupt the history bucket")
    func scopedDuplicateIsDropped() throws {
        let result = try windows(#"""
        {"seven_day_overage_included":{"utilization":80,"resets_at":1800400000},
         "limits":[{"kind":"weekly_scoped","percent":81,"resets_at":1800400000,
                    "scope":{"model":{"display_name":"Fable"}}}]}
        """#)
        #expect(result.count == 1)
        // Legacy key wins; one bucket, one window.
        #expect(abs((result.first?.usedFraction ?? 0) - 0.80) < 1e-9)
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
