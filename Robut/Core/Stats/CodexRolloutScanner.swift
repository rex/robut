// CodexRolloutScanner.swift — token accounting + account state from Codex
// rollouts.
//
// Each `token_count` event in `~/.codex/sessions/**/*.jsonl` carries the
// session's CUMULATIVE token totals (input, cached input, cache writes,
// output, reasoning) plus the full rate_limits object — which includes
// plan_type and credits that Robut previously ignored. Cumulative totals
// become per-event deltas via the cursor's last-seen total, attributed to
// the event's own timestamp; model comes from turn_context and project
// from session_meta, both remembered per file.

import Foundation

struct CodexScanResult: Sendable {
    var rollups: [String: DailyRollup] = [:]
    var hourly: [Int: TokenTally] = [:]
    var cursors: [String: FileCursor] = [:]
    var plan: CodexPlanInfo?
}

enum CodexRolloutScanner {

    static func scan(roots: [URL], cursors: [String: FileCursor]) -> CodexScanResult {
        var result = CodexScanResult()
        let calendar = Calendar.current

        for file in StatsScanning.jsonlFiles(under: roots) {
            let path = file.url.path
            var cursor = cursors[path] ?? FileCursor()
            if cursor.size == file.size, cursor.modified == file.modified {
                result.cursors[path] = cursor
                continue
            }
            if file.size < cursor.offset { cursor.offset = file.size }

            cursor.offset = StatsScanning.readLines(url: file.url, from: cursor.offset) { line in
                ingest(line: line, calendar: calendar, cursor: &cursor, into: &result)
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
        cursor: inout FileCursor,
        into result: inout CodexScanResult
    ) {
        // Only three line families matter; pre-filter before JSON parsing.
        let interesting = line.range(of: Data("token_count".utf8)) != nil
            || line.range(of: Data("turn_context".utf8)) != nil
            || line.range(of: Data("session_meta".utf8)) != nil
        guard interesting,
              let object = try? JSONSerialization.jsonObject(with: line),
              let entry = object as? [String: Any],
              let payload = entry["payload"] as? [String: Any]
        else { return }

        switch entry["type"] as? String {
        case "session_meta":
            cursor.project = payload["cwd"] as? String ?? cursor.project
        case "turn_context":
            cursor.model = payload["model"] as? String ?? cursor.model
        case "event_msg" where payload["type"] as? String == "token_count":
            guard let stampText = entry["timestamp"] as? String,
                  let stamp = StatsScanning.date(fromISO: stampText)
            else { return }
            if let info = payload["info"] as? [String: Any],
               let totals = info["total_token_usage"] as? [String: Any] {
                record(
                    total: tally(from: totals), at: stamp,
                    calendar: calendar, cursor: &cursor, into: &result
                )
            }
            if let limits = payload["rate_limits"] as? [String: Any] {
                recordPlan(from: limits, at: stamp, into: &result)
            }
        default:
            break
        }
    }

    private static func record(
        total: TokenTally,
        at stamp: Date,
        calendar: Calendar,
        cursor: inout FileCursor,
        into result: inout CodexScanResult
    ) {
        let previous = cursor.codexLastTotal ?? TokenTally()
        cursor.codexLastTotal = total

        var delta = TokenTally()
        delta.input = max(0, total.input - previous.input)
        delta.output = max(0, total.output - previous.output)
        delta.cacheRead = max(0, total.cacheRead - previous.cacheRead)
        delta.cacheWrite5m = max(0, total.cacheWrite5m - previous.cacheWrite5m)
        delta.reasoning = max(0, total.reasoning - previous.reasoning)
        guard delta.total > 0 else { return }

        let key = DailyRollup.key(
            day: StatsScanning.dayKey(stamp, calendar: calendar),
            provider: Provider.codex.rawValue,
            model: cursor.model ?? "unknown",
            project: cursor.project ?? "unknown"
        )
        var rollup = result.rollups[key] ?? DailyRollup(
            day: StatsScanning.dayKey(stamp, calendar: calendar),
            provider: Provider.codex.rawValue,
            model: cursor.model ?? "unknown",
            project: cursor.project ?? "unknown"
        )
        rollup.tally += delta
        rollup.messages += 1
        result.rollups[key] = rollup

        var hour = result.hourly[StatsScanning.hourKey(stamp)] ?? TokenTally()
        hour += delta
        result.hourly[StatsScanning.hourKey(stamp)] = hour
    }

    /// Codex cumulative totals use its own field names; cache writes land
    /// in the single `cacheWrite5m` bucket.
    private static func tally(from totals: [String: Any]) -> TokenTally {
        var tally = TokenTally()
        tally.input = totals["input_tokens"] as? Int ?? 0
        tally.output = totals["output_tokens"] as? Int ?? 0
        tally.cacheRead = totals["cached_input_tokens"] as? Int ?? 0
        tally.cacheWrite5m = totals["cache_write_input_tokens"] as? Int ?? 0
        tally.reasoning = totals["reasoning_output_tokens"] as? Int ?? 0
        // Codex counts cached input INSIDE input_tokens; split them so the
        // buckets don't double-count.
        tally.input = max(0, tally.input - tally.cacheRead)
        return tally
    }

    private static func recordPlan(
        from limits: [String: Any], at stamp: Date, into result: inout CodexScanResult
    ) {
        if let existing = result.plan, existing.asOf > stamp { return }
        var plan = CodexPlanInfo(asOf: stamp)
        plan.planType = limits["plan_type"] as? String
        if let credits = limits["credits"] as? [String: Any] {
            plan.hasCredits = credits["has_credits"] as? Bool
            plan.creditsUnlimited = credits["unlimited"] as? Bool
            plan.creditBalance = credits["balance"] as? String
        }
        result.plan = plan
    }
}
