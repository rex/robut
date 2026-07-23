// StatsScannerTests.swift — transcript scanners against synthetic fixtures.
//
// PUBLIC REPO: every fixture below is synthetic — invented paths, invented
// numbers — shaped like the real formats (captured 2026-07) but never
// copied from a real transcript.

import Foundation
import Testing

@testable import Robut

private func makeTempDir() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "robut-stats-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Claude transcript scanner")
struct ClaudeTranscriptScannerTests {

    private func transcriptLine(
        id: String, at: String, input: Int, output: Int, cacheRead: Int,
        sidechain: Bool = false
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(at)","cwd":"/tmp/proj-a","isSidechain":\(sidechain),\
        "message":{"id":"\(id)","model":"claude-opus-4-8","usage":{"input_tokens":0,"output_tokens":0,\
        "iterations":[{"input_tokens":\(input),"output_tokens":\(output),\
        "cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":50,\
        "cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":30},"type":"message"}]}}}
        """
    }

    @Test("Sums iteration tokens per day, model, and project — sidechains counted")
    func aggregates() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "session.jsonl", directoryHint: .notDirectory)
        let lines = [
            transcriptLine(id: "m1", at: "2026-01-05T12:00:00.000Z",
                           input: 100, output: 200, cacheRead: 1000),
            transcriptLine(id: "m2", at: "2026-01-05T13:00:00.000Z",
                           input: 10, output: 20, cacheRead: 500, sidechain: true),
            "{\"type\":\"user\",\"timestamp\":\"2026-01-05T12:01:00.000Z\"}",
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let result = ClaudeTranscriptScanner.scan(roots: [dir], cursors: [:])
        let rollup = try #require(result.rollups.values.first)
        #expect(result.rollups.count == 1)
        #expect(rollup.model == "claude-opus-4-8")
        #expect(rollup.project == "/tmp/proj-a")
        #expect(rollup.messages == 2)
        #expect(rollup.sidechainMessages == 1)
        #expect(rollup.tally.input == 110)
        #expect(rollup.tally.output == 220)
        #expect(rollup.tally.cacheRead == 1500)
        #expect(rollup.tally.cacheWrite5m == 40)
        #expect(rollup.tally.cacheWrite1h == 60)
        #expect(result.hourly.count == 2)
    }

    @Test("A message repeated by a retry counts once")
    func dedupesByMessageID() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "session.jsonl", directoryHint: .notDirectory)
        let line = transcriptLine(id: "same", at: "2026-01-05T12:00:00.000Z",
                                  input: 100, output: 200, cacheRead: 0)
        try [line, line].joined(separator: "\n").appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let result = ClaudeTranscriptScanner.scan(roots: [dir], cursors: [:])
        #expect(result.rollups.values.first?.messages == 1)
    }

    @Test("Incremental: a second scan reads only appended lines")
    func incremental() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "session.jsonl", directoryHint: .notDirectory)
        try transcriptLine(id: "m1", at: "2026-01-05T12:00:00.000Z", input: 100, output: 0, cacheRead: 0)
            .appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let first = ClaudeTranscriptScanner.scan(roots: [dir], cursors: [:])
        #expect(first.rollups.values.first?.tally.input == 100)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let extra = transcriptLine(id: "m2", at: "2026-01-05T14:00:00.000Z",
                                   input: 7, output: 0, cacheRead: 0) + "\n"
        try handle.write(contentsOf: Data(extra.utf8))
        try handle.close()

        let second = ClaudeTranscriptScanner.scan(roots: [dir], cursors: first.cursors)
        // The delta contains ONLY the appended message.
        #expect(second.rollups.values.reduce(0) { $0 + $1.tally.input } == 7)
    }
}

@Suite("Codex rollout scanner")
struct CodexRolloutScannerTests {

    private func tokenCountLine(at: String, input: Int, cached: Int, output: Int) -> String {
        """
        {"timestamp":"\(at)","type":"event_msg","payload":{"type":"token_count","info":\
        {"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
        "cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":5,\
        "total_tokens":\(input + output)}},"rate_limits":{"plan_type":"plus",\
        "credits":{"has_credits":false,"unlimited":false,"balance":"0"},\
        "primary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1785045214}}}}
        """
    }

    @Test("Cumulative totals become deltas; model and project stick; plan captured")
    func cumulativeDeltas() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "rollout.jsonl", directoryHint: .notDirectory)
        let lines = [
            "{\"timestamp\":\"2026-01-05T10:00:00.000Z\",\"type\":\"session_meta\","
                + "\"payload\":{\"cwd\":\"/tmp/proj-b\",\"cli_version\":\"1.0\"}}",
            "{\"timestamp\":\"2026-01-05T10:00:01.000Z\",\"type\":\"turn_context\","
                + "\"payload\":{\"model\":\"gpt-5.6-sol\"}}",
            tokenCountLine(at: "2026-01-05T10:05:00.000Z", input: 1000, cached: 600, output: 50),
            tokenCountLine(at: "2026-01-05T10:10:00.000Z", input: 3000, cached: 2000, output: 120),
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let result = CodexRolloutScanner.scan(roots: [dir], cursors: [:])
        let rollup = try #require(result.rollups.values.first)
        #expect(rollup.model == "gpt-5.6-sol")
        #expect(rollup.project == "/tmp/proj-b")
        // Non-cached input: (1000−600) + ((3000−2000)−(1000−600)) = 1000.
        #expect(rollup.tally.input == 1000)
        #expect(rollup.tally.cacheRead == 2000)
        #expect(rollup.tally.output == 120)
        #expect(result.plan?.planType == "plus")
        #expect(result.plan?.hasCredits == false)
    }

    @Test("Incremental: appended events yield only their delta")
    func incremental() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "rollout.jsonl", directoryHint: .notDirectory)
        try tokenCountLine(at: "2026-01-05T10:05:00.000Z", input: 100, cached: 0, output: 10)
            .appending("\n").write(to: file, atomically: true, encoding: .utf8)
        let first = CodexRolloutScanner.scan(roots: [dir], cursors: [:])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let extra = tokenCountLine(at: "2026-01-05T10:20:00.000Z", input: 150, cached: 0, output: 25) + "\n"
        try handle.write(contentsOf: Data(extra.utf8))
        try handle.close()

        let second = CodexRolloutScanner.scan(roots: [dir], cursors: first.cursors)
        #expect(second.rollups.values.reduce(0) { $0 + $1.tally.input } == 50)
        #expect(second.rollups.values.reduce(0) { $0 + $1.tally.output } == 15)
    }
}

@Suite("Prompt history scanner")
struct PromptHistoryScannerTests {

    @Test("Prompts, sessions, and projects roll up per day")
    func aggregates() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "history.jsonl", directoryHint: .notDirectory)
        let base = 1_800_000_000_000.0  // synthetic epoch millis, mid-day
        func promptLine(_ project: String, _ session: String, offset: Double) -> String {
            "{\"display\":\"p\",\"project\":\"\(project)\","
                + "\"sessionId\":\"\(session)\",\"timestamp\":\(base + offset)}"
        }
        let lines = [
            promptLine("/tmp/a", "s1", offset: 0),
            promptLine("/tmp/a", "s1", offset: 60_000),
            promptLine("/tmp/b", "s2", offset: 120_000),
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let result = PromptHistoryScanner.scan(file: file, cursor: FileCursor())
        let day = StatsScanning.dayKey(Date(timeIntervalSince1970: base / 1000))
        let activity = try #require(result.byDay[day])
        #expect(activity.prompts == 3)
        #expect(activity.sessionIDs.count == 2)
        #expect(activity.projects == ["/tmp/a", "/tmp/b"])
    }
}
