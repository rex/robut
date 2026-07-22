// CodexUsageSourceTests.swift — parsing Codex rollout files.
//
// PUBLIC REPO: every fixture here is synthesized in a temp directory.
// Never copy a real rollout file into this repo — they contain prompts,
// account identifiers, and file paths.

import Foundation
import Testing

@testable import Robut

@Suite("Codex usage source")
struct CodexUsageSourceTests {

    /// Builds a throwaway ~/.codex/sessions tree containing one rollout
    /// file with the given entries.
    private func makeFixture(lines: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "robut-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let day = root.appending(path: "2026/07/22", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appending(path: "rollout-synthetic.jsonl", directoryHint: .notDirectory)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return root
    }

    /// One `token_count` event carrying a rate_limits payload.
    private func entry(
        timestamp: String,
        usedPercent: Double,
        windowMinutes: Int,
        resetsAt: Int,
        secondary: String = "null"
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
        "rate_limits":{"limit_id":"codex","primary":{"used_percent":\(usedPercent),\
        "window_minutes":\(windowMinutes),"resets_at":\(resetsAt)},"secondary":\(secondary),\
        "plan_type":"synthetic"}}}
        """
    }

    @Test("A missing sessions directory is notConfigured, not an error")
    func missingDirectory() async {
        let source = CodexUsageSource(
            sessionsRoot: URL(fileURLWithPath: "/nonexistent/robut/test/path")
        )
        if case .notConfigured = await source.fetch(now: t0) { } else {
            Issue.record("Expected .notConfigured for a missing sessions directory")
        }
    }

    @Test("Reads the most recent rate_limits payload")
    func readsLatest() async throws {
        let root = try makeFixture(lines: [
            entry(timestamp: "2026-07-22T10:00:00.000Z", usedPercent: 10,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
            // An unrelated event between the two that must be ignored.
            #"{"timestamp":"2026-07-22T10:30:00Z","type":"event_msg","payload":{"type":"agent"}}"#,
            entry(timestamp: "2026-07-22T11:00:00.000Z", usedPercent: 42,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let state = await CodexUsageSource(sessionsRoot: root).fetch(now: t0)
        let snapshot = try #require(state.snapshot)

        #expect(snapshot.provider == .codex)
        #expect(snapshot.planLabel == "synthetic")
        #expect(snapshot.windows.count == 1)
        // Latest entry wins: 42%, not the earlier 10%.
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.42) < 0.0001)
        #expect(snapshot.windows.first?.kind == .weekly)
    }

    @Test("Both primary and secondary windows are surfaced")
    func bothWindows() async throws {
        let secondary = #"{"used_percent":8.0,"window_minutes":300,"resets_at":1800005000}"#
        let root = try makeFixture(lines: [
            entry(timestamp: "2026-07-22T11:00:00.000Z", usedPercent: 55,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000, secondary: secondary),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let state = await CodexUsageSource(sessionsRoot: root).fetch(now: t0)
        let snapshot = try #require(state.snapshot)

        #expect(snapshot.windows.count == 2)
        // Short windows sort first — that's the one that bites soonest.
        #expect(snapshot.windows.first?.kind == .session)
        #expect(snapshot.windows.last?.kind == .weekly)
    }

    @Test("Percentages are normalized and clamped to 0...1")
    func clampsPercent() async throws {
        let root = try makeFixture(lines: [
            entry(timestamp: "2026-07-22T11:00:00.000Z", usedPercent: 140,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let state = await CodexUsageSource(sessionsRoot: root).fetch(now: t0)
        #expect(state.snapshot?.windows.first?.usedFraction == 1.0)
    }

    @Test("Malformed lines are skipped rather than failing the read")
    func toleratesGarbage() async throws {
        let root = try makeFixture(lines: [
            "not json at all",
            #"{"rate_limits": "this is the wrong shape"}"#,
            entry(timestamp: "2026-07-22T11:00:00.000Z", usedPercent: 30,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let state = await CodexUsageSource(sessionsRoot: root).fetch(now: t0)
        #expect(abs((state.snapshot?.windows.first?.usedFraction ?? 0) - 0.30) < 0.0001)
    }

    @Test("Backfill returns every historical payload, oldest first")
    func backfillOrdering() async throws {
        let root = try makeFixture(lines: [
            entry(timestamp: "2026-07-22T09:00:00.000Z", usedPercent: 10,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
            entry(timestamp: "2026-07-22T10:00:00.000Z", usedPercent: 20,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
            entry(timestamp: "2026-07-22T11:00:00.000Z", usedPercent: 35,
                  windowMinutes: 10_080, resetsAt: 1_800_100_000),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshots = await CodexUsageSource(sessionsRoot: root).backfill()

        #expect(snapshots.count == 3)
        #expect(snapshots == snapshots.sorted { $0.sampledAt < $1.sampledAt })
        // Oldest first, so history replays in the order it happened.
        #expect(abs((snapshots.first?.windows.first?.usedFraction ?? 0) - 0.10) < 0.0001)
        #expect(abs((snapshots.last?.windows.first?.usedFraction ?? 0) - 0.35) < 0.0001)
    }
}
