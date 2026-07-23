// ClaudeUsageInsightsParser.swift — the analytics block Robut used to
// throw away.
//
// Under its limit lines, `claude /usage` prints a "What's contributing to
// your limits usage?" section: rolling 24h/7d request+session counts,
// behavioral traits, and top skills/subagents/MCP servers by share. This
// parser lifts that whole block. Format captured from real output
// (2026-07); tolerant by construction — anything unrecognized is skipped,
// and an output with no section headers parses to nil.

import Foundation

enum ClaudeUsageInsightsParser {

    static func insights(from text: String, capturedAt: Date) -> UsageInsights? {
        var windows: [InsightsWindow] = []
        var current: InsightsWindow?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let header = parseHeader(line) {
                if let finished = current { windows.append(finished) }
                current = header
                continue
            }
            guard current != nil else { continue }

            if let trait = parseTrait(line) {
                current?.traits.append(trait)
            } else if let (kind, shares) = parseTopList(line) {
                switch kind {
                case "skills": current?.topSkills = shares
                case "subagents": current?.topSubagents = shares
                default: current?.topMCPServers = shares
                }
            }
        }
        if let finished = current { windows.append(finished) }

        guard !windows.isEmpty else { return nil }
        return UsageInsights(capturedAt: capturedAt, windows: windows)
    }

    // MARK: - Line parsers

    /// "Last 24h · 1905 requests · 6 sessions"
    private static func parseHeader(_ line: String) -> InsightsWindow? {
        let pattern = /Last (24h|7d) · ([\d,]+) requests? · ([\d,]+) sessions?/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        return InsightsWindow(
            period: String(match.1),
            requests: number(match.2),
            sessions: number(match.3),
            traits: [], topSkills: [], topSubagents: [], topMCPServers: []
        )
    }

    /// "84% of your usage was at >150k context" — the share plus the
    /// label after "was at" / "came from".
    private static func parseTrait(_ line: String) -> InsightShare? {
        let pattern = /^(\d+)% of your usage (?:was at|came from) (.+)$/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        return InsightShare(name: String(match.2), sharePercent: Int(match.1) ?? 0)
    }

    /// "Top subagents: workflow-subagent 23%, general-purpose 12%, +1 more"
    private static func parseTopList(_ line: String) -> (String, [InsightShare])? {
        let pattern = /^Top (skills|subagents|MCP servers): (.+)$/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let shares = String(match.2)
            .split(separator: ",")
            .compactMap { item -> InsightShare? in
                let entry = item.trimmingCharacters(in: .whitespaces)
                // Name can contain spaces; the share is the trailing "N%".
                guard let shareMatch = entry.firstMatch(of: /^(.+?)\s+(\d+)%$/) else { return nil }
                return InsightShare(
                    name: String(shareMatch.1),
                    sharePercent: Int(shareMatch.2) ?? 0
                )
            }
        guard !shares.isEmpty else { return nil }
        return (String(match.1), shares)
    }

    private static func number(_ digits: Substring) -> Int {
        Int(digits.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
