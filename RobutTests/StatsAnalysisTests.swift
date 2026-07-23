// StatsAnalysisTests.swift — the insights parser, price table, quota
// estimator, and stats-store persistence. All fixtures synthetic.

import Foundation
import Testing

@testable import Robut

@Suite("Usage insights parser")
struct InsightsParserTests {

    /// Shaped like the CLI's real analytics block; numbers invented.
    private let sample = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 12% used · resets Jan 5 at 2pm (UTC)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine.

    Last 24h · 1,234 requests · 5 sessions
      80% of your usage was at >150k context
      42% of your usage came from sessions active for 8+ hours
      Top skills: /example 3%
      Top subagents: helper-agent 20%, general-purpose 10%
      Top MCP servers: some server 15%, another 2%, +1 more

    Last 7d · 9,876 requests · 30 sessions
      91% of your usage was at >150k context
    """

    @Test("Both rolling windows parse with counts, traits, and top lists")
    func parsesFullBlock() throws {
        let insights = try #require(
            ClaudeUsageInsightsParser.insights(from: sample, capturedAt: t0)
        )
        #expect(insights.windows.count == 2)

        let day = try #require(insights.windows.first { $0.period == "24h" })
        #expect(day.requests == 1234)
        #expect(day.sessions == 5)
        #expect(day.traits.count == 2)
        #expect(day.traits.first?.sharePercent == 80)
        #expect(day.topSkills == [InsightShare(name: "/example", sharePercent: 3)])
        #expect(day.topSubagents.count == 2)
        #expect(day.topSubagents.first == InsightShare(name: "helper-agent", sharePercent: 20))
        // Multi-word names keep their spaces; "+1 more" tails are dropped.
        #expect(day.topMCPServers.first == InsightShare(name: "some server", sharePercent: 15))
        #expect(day.topMCPServers.count == 2)

        let week = try #require(insights.windows.first { $0.period == "7d" })
        #expect(week.requests == 9876)
        #expect(week.sessions == 30)
    }

    @Test("Output without the analytics section parses to nil, not garbage")
    func noSection() {
        let text = "Current session: 3% used · resets Jan 5 at 2pm (UTC)"
        #expect(ClaudeUsageInsightsParser.insights(from: text, capturedAt: t0) == nil)
    }
}

@Suite("Price table")
struct PriceTableTests {

    @Test("Costs combine every bucket at its own rate")
    func costMath() throws {
        var tally = TokenTally()
        tally.input = 1_000_000
        tally.output = 1_000_000
        tally.cacheRead = 1_000_000
        // Opus: $5 in + $25 out + $0.50 cache-read = $30.50.
        let usd = try #require(PriceTable.cost(of: tally, model: "claude-opus-4-8"))
        #expect(abs(usd - 30.50) < 0.001)
    }

    @Test("Dated model ids resolve by prefix; unknown models return nil")
    func prefixMatching() {
        #expect(PriceTable.price(forModel: "claude-haiku-4-5-20251001") != nil)
        #expect(PriceTable.price(forModel: "gpt-5.6-sol")?.output == 30.00)
        // Generic gpt-5 fallback must not shadow the specific tier.
        #expect(PriceTable.price(forModel: "gpt-5.6-luna")?.input == 1.00)
        #expect(PriceTable.cost(of: TokenTally(), model: "mystery-model-9") == nil)
    }
}

@Suite("Quota estimator")
struct QuotaEstimatorTests {

    @Test("Percent moves correlate with hourly tokens into tokens-per-percent")
    func correlates() throws {
        // Two clean intervals: 2% ↔ 200k tokens, then 3% ↔ 300k tokens
        // → 100k tokens per percent, a 10M-token window.
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-6 * 3600), usedFraction: 0.10),
            UsageSample(at: t0.addingTimeInterval(-4 * 3600), usedFraction: 0.12),
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.15),
        ]
        // Buckets kept clear of the shared interval boundary (−4h): the
        // sum is bucket-granular with inclusive ends, so a boundary bucket
        // would count toward both intervals.
        var hourly: [Int: TokenTally] = [:]
        for (hoursAgo, tokens) in [(6, 100_000), (5, 100_000), (3, 300_000)] {
            var tally = TokenTally()
            tally.input = tokens
            hourly[StatsScanning.hourKey(t0.addingTimeInterval(-Double(hoursAgo) * 3600))] = tally
        }

        let estimate = try #require(QuotaEstimator.estimate(
            windowID: "claude.weekly", samples: samples, hourlyTokens: hourly, now: t0
        ))
        #expect(abs(estimate.tokensPerPercent - 100_000) < 20_000)
        #expect(estimate.sampleCount == 2)
    }

    @Test("Resets and sub-point noise produce no estimate rather than a wrong one")
    func refusesThinEvidence() {
        let samples = [
            UsageSample(at: t0.addingTimeInterval(-2 * 3600), usedFraction: 0.90),
            UsageSample(at: t0.addingTimeInterval(-1 * 3600), usedFraction: 0.05),  // reset
            UsageSample(at: t0, usedFraction: 0.052),                               // noise
        ]
        #expect(QuotaEstimator.estimate(
            windowID: "codex.weekly", samples: samples, hourlyTokens: [:], now: t0
        ) == nil)
    }
}

@Suite("Usage stats store")
struct UsageStatsStoreTests {

    @Test("Ingested insights and scans persist across a reopen")
    func roundTrips() async throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "robut-stats-\(UUID().uuidString).json", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: file) }

        let store = UsageStatsStore(fileURL: file)
        let text = """
        Last 24h · 42 requests · 2 sessions
          50% of your usage was at >150k context
        """
        await store.ingest(usageText: text, at: t0)

        let reopened = UsageStatsStore(fileURL: file)
        let snapshot = await reopened.snapshot()
        #expect(snapshot.insights?.windows.first?.requests == 42)
        #expect(snapshot.insightsByDay[StatsScanning.dayKey(t0)]?.sessions == 2)
    }
}
