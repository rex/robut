// ClaudeTranscriptScanner.swift — token accounting from Claude Code's own
// transcripts.
//
// Every assistant message in `~/.claude/projects/**/*.jsonl` carries a
// `usage` object: input/output tokens, cache reads, cache writes (with
// 5m/1h TTL tiers), the model, a timestamp, the working directory, and
// whether it was a subagent (`isSidechain`). That is a complete local
// ledger — daily/30d token totals, per-model and per-project splits, and
// API-equivalent cost all fall out of it.
//
// Read-only, incremental (FileCursor per file), and machine-local by
// nature: this ledger covers Claude Code on THIS Mac, not claude.ai or
// other devices. The account-wide truth remains the percentage windows.

import Foundation

struct ClaudeScanResult: Sendable {
    var rollups: [String: DailyRollup] = [:]
    var hourly: [Int: TokenTally] = [:]
    var cursors: [String: FileCursor] = [:]
}

enum ClaudeTranscriptScanner {

    static func scan(roots: [URL], cursors: [String: FileCursor]) -> ClaudeScanResult {
        var result = ClaudeScanResult()
        let calendar = Calendar.current
        // Retries can duplicate a message within a scan; dedupe by id.
        var seenMessageIDs: Set<String> = []

        for file in StatsScanning.jsonlFiles(under: roots) {
            let path = file.url.path
            var cursor = cursors[path] ?? FileCursor()
            if cursor.size == file.size, cursor.modified == file.modified {
                result.cursors[path] = cursor
                continue
            }
            // A shrunk file was rewritten; skip to its end, never re-count.
            if file.size < cursor.offset { cursor.offset = file.size }

            cursor.offset = StatsScanning.readLines(url: file.url, from: cursor.offset) { line in
                ingest(
                    line: line, calendar: calendar,
                    seen: &seenMessageIDs, into: &result
                )
            }
            cursor.size = file.size
            cursor.modified = file.modified
            result.cursors[path] = cursor
        }
        return result
    }

    // MARK: - Per-line

    private static func ingest(
        line: Data,
        calendar: Calendar,
        seen: inout Set<String>,
        into result: inout ClaudeScanResult
    ) {
        // Cheap pre-filter before paying for JSON parsing.
        guard line.range(of: Data("\"assistant\"".utf8)) != nil,
              line.range(of: Data("\"usage\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line),
              let entry = object as? [String: Any],
              entry["type"] as? String == "assistant",
              let message = entry["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stampText = entry["timestamp"] as? String,
              let stamp = StatsScanning.date(fromISO: stampText)
        else { return }

        if let messageID = message["id"] as? String {
            guard seen.insert(messageID).inserted else { return }
        }

        let tally = tally(from: usage)
        guard tally.total > 0 else { return }

        let sidechain = entry["isSidechain"] as? Bool ?? false
        let key = DailyRollup.key(
            day: StatsScanning.dayKey(stamp, calendar: calendar),
            provider: Provider.claude.rawValue,
            model: message["model"] as? String ?? "unknown",
            project: entry["cwd"] as? String ?? "unknown"
        )
        var rollup = result.rollups[key] ?? seedRollup(fromKey: key)
        rollup.tally += tally
        rollup.messages += 1
        if sidechain { rollup.sidechainMessages += 1 }
        result.rollups[key] = rollup

        var hour = result.hourly[StatsScanning.hourKey(stamp)] ?? TokenTally()
        hour += tally
        result.hourly[StatsScanning.hourKey(stamp)] = hour
    }

    /// Newer Claude Code versions put the real numbers in
    /// `usage.iterations` (top-level fields are often zero); older lines
    /// carry them at top level. Prefer iterations when present.
    static func tally(from usage: [String: Any]) -> TokenTally {
        if let iterations = usage["iterations"] as? [[String: Any]], !iterations.isEmpty {
            var sum = TokenTally()
            for iteration in iterations { sum += singleTally(from: iteration) }
            return sum
        }
        return singleTally(from: usage)
    }

    private static func singleTally(from usage: [String: Any]) -> TokenTally {
        var tally = TokenTally()
        tally.input = usage["input_tokens"] as? Int ?? 0
        tally.output = usage["output_tokens"] as? Int ?? 0
        tally.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        if let creation = usage["cache_creation"] as? [String: Any] {
            tally.cacheWrite5m = creation["ephemeral_5m_input_tokens"] as? Int ?? 0
            tally.cacheWrite1h = creation["ephemeral_1h_input_tokens"] as? Int ?? 0
        } else {
            tally.cacheWrite5m = usage["cache_creation_input_tokens"] as? Int ?? 0
        }
        return tally
    }

    private static func seedRollup(fromKey key: String) -> DailyRollup {
        let parts = key.split(separator: "|", maxSplits: 3).map(String.init)
        return DailyRollup(
            day: parts.first ?? "",
            provider: parts.count > 1 ? parts[1] : "",
            model: parts.count > 2 ? parts[2] : "",
            project: parts.count > 3 ? parts[3] : ""
        )
    }
}
