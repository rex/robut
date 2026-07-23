// ClaudeUsageTextParser.swift — turn `claude /usage` output into windows.
//
// Written against the REAL output of `claude -p "/usage"`, captured from a
// signed-in machine:
//
//   Current session: 3% used · resets Jul 23 at 1:59pm (America/Chicago)
//   Current week (all models): 5% used · resets Jul 30 at 2:59am (America/Chicago)
//   Current week (Fable): 0% used
//
// The rest of /usage is a "what's contributing" breakdown full of lines
// like "55% of your usage came from … sessions" — which must NOT be
// mistaken for windows. So only lines that begin with "Current session"
// or "Current week" are treated as usage limits.
//
// Pure: text in, windows out, injected clock. No I/O.

import Foundation

enum ClaudeUsageTextParser {

    /// Best-effort extraction. Returns [] rather than guessing when a line
    /// can't be read — a missing row is honest, a fabricated one is not.
    static func windows(from text: String, now: Date) -> [UsageWindow] {
        var found: [UsageWindow] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let shape = shape(of: line) else { continue }
            guard let percent = percentage(in: line) else { continue }

            let length = TimeInterval(shape.minutes * 60)
            found.append(UsageWindow(
                provider: .claude,
                kind: UsageWindow.Kind(windowMinutes: shape.minutes),
                variant: shape.variant,
                usedFraction: min(1, max(0, percent / 100)),
                resetsAt: resetDate(in: line, now: now) ?? now.addingTimeInterval(length),
                length: length
            ))
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Line classification

    private struct Shape { let minutes: Int; let variant: String? }

    /// Only genuine usage-limit lines: "Current session" or "Current week
    /// (...)". Everything else in /usage is skipped. Variant keywords are
    /// checked before the generic weekly so "(Opus)" isn't swallowed by
    /// "week".
    private static func shape(of line: String) -> Shape? {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("current session") { return Shape(minutes: 300, variant: nil) }
        guard lower.hasPrefix("current week") else { return nil }
        if lower.contains("(fable)") { return Shape(minutes: 10_080, variant: "Fable") }
        if lower.contains("(sonnet)") { return Shape(minutes: 10_080, variant: "Sonnet") }
        if lower.contains("(opus)") { return Shape(minutes: 10_080, variant: "Opus") }
        return Shape(minutes: 10_080, variant: nil)   // "(all models)" / unlabelled
    }

    // MARK: - Numbers

    /// First percentage on the line, e.g. "3% used".
    static func percentage(in line: String) -> Double? {
        guard let range = line.range(
            of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression
        ) else { return nil }
        let digits = line[range].filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    // MARK: - Reset time

    /// Accepts the absolute form the CLI actually prints, falling back to
    /// the relative form for safety.
    static func resetDate(in line: String, now: Date) -> Date? {
        absoluteReset(in: line, now: now) ?? relativeReset(in: line, now: now)
    }

    /// Parses the absolute reset the CLI prints, in the named timezone.
    /// The time appears both on the hour ("resets Jul 30 at 3am") and with
    /// minutes ("resets Jul 23 at 1:59pm") — the minutes are optional. The
    /// year is inferred (resets are days out, never months), bumping to
    /// next year if the date already passed.
    static func absoluteReset(in line: String, now: Date) -> Date? {
        // Groups: 1=month 2=day 3=hour 4=minute(optional) 5=am/pm 6=tz(optional)
        let pattern = #"resets\s+([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+at\s+"#
            + #"(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let text = line as NSString
        guard let match = regex.firstMatch(
            in: line, range: NSRange(location: 0, length: text.length)
        ) else { return nil }

        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }

        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        guard let monthName = group(1)?.lowercased(), let month = months[monthName],
              let day = group(2).flatMap(Int.init),
              var hour = group(3).flatMap(Int.init),
              let meridiem = group(5)?.lowercased()
        else { return nil }
        let minute = group(4).flatMap(Int.init) ?? 0   // "3am" has no minutes

        if meridiem == "pm", hour != 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }

        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = group(6).flatMap(TimeZone.init(identifier:)) {
            calendar.timeZone = timeZone
        }

        var components = DateComponents()
        components.year = calendar.component(.year, from: now)
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        guard let date = calendar.date(from: components) else { return nil }
        // Already well past → it must mean next year's occurrence.
        if date < now.addingTimeInterval(-86_400) {
            components.year = (components.year ?? 0) + 1
            return calendar.date(from: components)
        }
        return date
    }

    /// "resets in 3h 20m" — a defensive fallback; the current CLI prints
    /// absolute times, but older/other formats may be relative.
    static func relativeReset(in line: String, now: Date) -> Date? {
        let lower = line.lowercased()
        guard let resetsRange = lower.range(of: "reset") else { return nil }
        let tail = String(lower[resetsRange.upperBound...])

        var seconds: TimeInterval = 0
        var matched = false
        let units: [(String, Double)] = [(#"(\d+)\s*d"#, 86_400), (#"(\d+)\s*h"#, 3_600), (#"(\d+)\s*m"#, 60)]
        for (pattern, multiplier) in units {
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
