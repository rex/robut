// StatsModels.swift — the value types of the usage-statistics domain.
//
// Everything Robut captures beyond the live percentages lands in these
// shapes: token accounting scanned from provider transcripts, the CLI's
// own usage analytics, prompt activity, plan/credit state, and the
// tokens-per-percent quota estimates. Deliberately dumb — no I/O.

import Foundation

/// Token counts, one accounting bucket per kind the providers report.
/// Claude's cache writes split by TTL tier; Codex reports `reasoning`
/// (a subset of `output`, kept for visibility) and a single cache-write
/// bucket (stored in `cacheWrite5m`).
struct TokenTally: Sendable, Hashable, Codable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var reasoning = 0

    /// Raw volume across every bucket (reasoning excluded — it is
    /// already counted inside `output`).
    var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    static func += (lhs: inout TokenTally, rhs: TokenTally) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheRead += rhs.cacheRead
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
        lhs.reasoning += rhs.reasoning
    }
}

/// One day × provider × model × project aggregation bucket.
struct DailyRollup: Sendable, Hashable, Codable {
    var day: String          // "2026-07-23" (local calendar day)
    var provider: String     // "claude" | "codex"
    var model: String        // e.g. "claude-opus-4-8", "gpt-5.6-sol"
    var project: String      // cwd the work happened in ("unknown" if absent)
    var tally = TokenTally()
    var messages = 0
    var sidechainMessages = 0  // subagent messages (Claude `isSidechain`)

    static func key(day: String, provider: String, model: String, project: String) -> String {
        "\(day)|\(provider)|\(model)|\(project)"
    }

    var key: String { Self.key(day: day, provider: provider, model: model, project: project) }
}

/// A named share within the CLI's usage analytics ("workflow-subagent 23%").
struct InsightShare: Sendable, Hashable, Codable {
    var name: String
    var sharePercent: Int
}

/// One rolling window of `claude /usage` analytics (24h or 7d).
struct InsightsWindow: Sendable, Hashable, Codable {
    var period: String       // "24h" | "7d"
    var requests: Int
    var sessions: Int
    /// Behavioral traits ("of your usage was at >150k context" → 84).
    var traits: [InsightShare]
    var topSkills: [InsightShare]
    var topSubagents: [InsightShare]
    var topMCPServers: [InsightShare]
}

/// The analytics block the CLI prints under the limit lines. Rolling
/// windows, machine-local, Claude-Code-only — per the CLI's own caveat.
struct UsageInsights: Sendable, Hashable, Codable {
    var capturedAt: Date
    var windows: [InsightsWindow]
}

/// One day's prompt activity from `~/.claude/history.jsonl`.
struct PromptActivity: Sendable, Hashable, Codable {
    var prompts = 0
    var sessionIDs: Set<String> = []
    var projects: Set<String> = []
}

/// Codex account state carried in every rollout's rate_limits.
struct CodexPlanInfo: Sendable, Hashable, Codable {
    var planType: String?
    var hasCredits: Bool?
    var creditsUnlimited: Bool?
    var creditBalance: String?
    var asOf: Date
}

/// Tokens-per-percent correlation for one usage window — the derived
/// stat that turns percentages into absolute token estimates.
struct QuotaEstimate: Sendable, Hashable, Codable {
    var windowID: String
    /// Local tokens consumed per 1% of the window's quota.
    var tokensPerPercent: Double
    /// tokensPerPercent × 100 — the implied full window, in tokens.
    var estimatedWindowTokens: Double
    var sampleCount: Int
    var asOf: Date
}

/// The complete read model — everything captured, for display layers.
struct StatsSnapshot: Sendable {
    var daily: [DailyRollup]
    var hourly: [String: TokenTally]          // "provider|hourEpoch"
    var insights: UsageInsights?
    var insightsByDay: [String: InsightsWindow]  // day → that day's 24h window
    var promptsByDay: [String: PromptActivity]
    var codexPlan: CodexPlanInfo?
    var quotaEstimates: [String: QuotaEstimate]  // windowID → estimate
    var lastScan: Date?
}
