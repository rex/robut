// PaceFormatting.swift — turning verdicts into sentences a human wants.
//
// The wording matters more than it looks. "84% used" is a fact; "you'll run
// dry about 9h early" is an answer. Robut always leads with the answer.

import Foundation

enum PaceFormatting {

    /// The headline for one window — the sentence the app exists to print.
    static func verdictText(_ verdict: PaceVerdict) -> String {
        switch verdict.outlook {
        case .exhausted:
            "Quota spent"
        case .unknown:
            "Measuring pace…"
        case .idle:
            "Idle — you'll make it"
        case .comfortable:
            if let headroom = verdict.headroomAtReset {
                "On track — ~\(percent(headroom)) to spare"
            } else {
                "On track"
            }
        case .tight:
            "Cutting it close — barely makes it"
        case .shortfall:
            if let short = verdict.shortfall {
                "Runs dry ~\(duration(short)) early"
            } else {
                "Will run out before reset"
            }
        }
    }

    /// Secondary line: the actual numbers, for when the headline isn't enough.
    static func detailText(_ verdict: PaceVerdict) -> String? {
        guard let burn = verdict.burnPerHour, burn > 0 else { return nil }
        let current = "\(percent(burn))/hr now"
        guard verdict.safePerHour.isFinite, verdict.safePerHour > 0 else { return current }
        return "\(current) · \(percent(verdict.safePerHour))/hr sustainable"
    }

    /// "2d 4h", "9h", "35m" — coarse on purpose. False precision on an
    /// estimate is a lie with extra steps.
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// Fractions render as whole percents; below 1% we say "<1%" rather
    /// than "0%", because zero and nearly-zero mean different things.
    static func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    static func resetText(_ resetsAt: Date, now: Date) -> String {
        let remaining = resetsAt.timeIntervalSince(now)
        return remaining <= 0 ? "resetting…" : "resets in \(duration(remaining))"
    }
}
