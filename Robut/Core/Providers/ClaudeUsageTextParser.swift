// ClaudeUsageTextParser.swift — turn `claude /usage` output into windows.
//
// ⚠️ PROVISIONAL. This parser was written WITHOUT a real sample of the
// command's output, because verifying it costs a live call to an endpoint
// that had just rate-limited the machine. It is deliberately tolerant and
// deliberately isolated: when a real sample arrives, this is the only
// file that should need to change. Capture one safely with:
//
//     make claude-probe
//
// Everything here is pure — text in, windows out, injected clock. No I/O,
// no process spawning; those live in ClaudeCLIUsageSource.

import Foundation

enum ClaudeUsageTextParser {

    /// Best-effort extraction. Returns [] rather than guessing when a line
    /// can't be read — a missing row is honest, a fabricated one is not.
    static func windows(from text: String, now: Date) -> [UsageWindow] {
        var found: [UsageWindow] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let raw = String(line)
            guard let percent = percentage(in: raw) else { continue }
            guard let shape = shape(of: raw) else { continue }

            found.append(UsageWindow(
                provider: .claude,
                kind: UsageWindow.Kind(windowMinutes: shape.minutes),
                variant: shape.variant,
                usedFraction: min(1, max(0, percent / 100)),
                resetsAt: resetDate(in: raw, now: now)
                    ?? now.addingTimeInterval(TimeInterval(shape.minutes * 60)),
                length: TimeInterval(shape.minutes * 60)
            ))
        }

        // Same window mentioned twice (e.g. a summary line plus a detail
        // line) — keep the first, which is nearest the heading.
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Line classification

    private struct Shape {
        let minutes: Int
        let variant: String?
    }

    /// Which window a line is talking about, by keyword. Opus is checked
    /// first because an Opus line also says "week".
    private static func shape(of line: String) -> Shape? {
        let lower = line.lowercased()

        if lower.contains("opus") {
            return Shape(minutes: 10_080, variant: "Opus")
        }
        if matches(lower, ["week", "7-day", "7 day", "seven-day", "seven day"]) {
            return Shape(minutes: 10_080, variant: nil)
        }
        if matches(lower, ["session", "5-hour", "5 hour", "five-hour", "five hour"]) {
            return Shape(minutes: 300, variant: nil)
        }
        return nil
    }

    private static func matches(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    // MARK: - Numbers

    /// First percentage on the line, e.g. "42%" or "42.5 %".
    static func percentage(in line: String) -> Double? {
        guard let range = line.range(
            of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression
        ) else { return nil }
        let digits = line[range].filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    /// Reset time, accepting the relative forms the CLI is likely to use
    /// ("resets in 3h 20m", "resets in 2 days"). Absolute clock times are
    /// deliberately NOT guessed at — an unparsed reset falls back to the
    /// window length, which is wrong by at most one window instead of
    /// wrong by a timezone.
    static func resetDate(in line: String, now: Date) -> Date? {
        let lower = line.lowercased()
        guard let resetsRange = lower.range(of: "reset") else { return nil }
        let tail = String(lower[resetsRange.upperBound...])

        var seconds: TimeInterval = 0
        var matched = false
        for (pattern, multiplier) in [
            (#"(\d+)\s*d"#, 86_400.0),
            (#"(\d+)\s*h"#, 3_600.0),
            (#"(\d+)\s*m"#, 60.0),
        ] {
            guard let range = tail.range(of: pattern, options: .regularExpression) else { continue }
            let digits = tail[range].filter(\.isNumber)
            guard let value = Double(digits) else { continue }
            seconds += value * multiplier
            matched = true
        }

        guard matched, seconds > 0 else { return nil }
        return now.addingTimeInterval(seconds)
    }
}
