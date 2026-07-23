// ClaudeCLIUsageTests.swift — the CLI fallback and its text parser.
//
// The parser is provisional (written without a real sample), so these
// tests pin the BEHAVIOUR that must hold regardless of exact wording:
// never fabricate a window, never fall back on a rate limit, prefer the
// token path when it works. When a real sample arrives, expect the
// wording cases to change and these invariants to stay.
//
// No process is ever spawned: the runner is injected.

import Foundation
import Testing

@testable import Robut

@Suite("Claude usage text parser")
struct ClaudeUsageTextParserTests {

    /// VERBATIM `claude -p "/usage"` output from a signed-in machine.
    private let realUsage = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 3% used · resets Jul 23 at 1:59pm (America/Chicago)
    Current week (all models): 5% used · resets Jul 30 at 2:59am (America/Chicago)
    Current week (Fable): 0% used

    What's contributing to your limits usage?
    Last 24h · 1990 requests · 6 sessions
      55% of your usage came from subagent-heavy sessions
      Top skills: /scaffold 4%
    """

    @Test("Parses the real /usage output into exactly the three windows")
    func realOutput() {
        let windows = ClaudeUsageTextParser.windows(from: realUsage, now: t0)
        let ids = Set(windows.map(\.id))
        #expect(ids == ["claude.session", "claude.weekly", "claude.weekly.Fable"])
        #expect(abs((windows.first { $0.id == "claude.weekly" }?.usedFraction ?? -1) - 0.05) < 0.0001)
    }

    @Test("Stat lines like '55% … sessions' are NOT mistaken for windows")
    func statLinesIgnored() {
        // The failure this guards: "55% of your usage came from … sessions"
        // contains "session" and a percent, but is not a usage limit.
        let windows = ClaudeUsageTextParser.windows(from: realUsage, now: t0)
        #expect(windows.count == 3)
        #expect(!windows.contains { $0.usedFraction > 0.5 })   // no 55% window
    }

    @Test("Percentages are read regardless of spacing")
    func percentages() {
        #expect(ClaudeUsageTextParser.percentage(in: "3% used") == 3)
        #expect(ClaudeUsageTextParser.percentage(in: "Session: 42.5 %") == 42.5)
        #expect(ClaudeUsageTextParser.percentage(in: "no numbers here") == nil)
    }

    @Test("An absolute reset date is parsed in its stated timezone")
    func absoluteReset() throws {
        let line = "Current week (all models): 5% used · resets Jul 30 at 2:59am (America/Chicago)"
        let date = try #require(ClaudeUsageTextParser.resetDate(in: line, now: t0))
        // Jul 30 2:59am America/Chicago (CDT, UTC-5) == 07:59 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let comps = utc.dateComponents([.month, .day, .hour, .minute], from: date)
        #expect(comps.month == 30 || comps.day == 30)   // day 30
        #expect(comps.hour == 7 && comps.minute == 59)   // 2:59am CDT = 07:59 UTC
    }

    @Test("Relative reset times still parse (defensive fallback)")
    func relativeReset() throws {
        let date = try #require(ClaudeUsageTextParser.resetDate(in: "resets in 3h 20m", now: t0))
        #expect(abs(date.timeIntervalSince(t0) - (3 * 3600 + 20 * 60)) < 1)
    }

    @Test("Fable with no reset field falls back, never fabricates a percent")
    func fableNoReset() {
        let windows = ClaudeUsageTextParser.windows(from: "Current week (Fable): 0% used", now: t0)
        #expect(windows.count == 1)
        #expect(windows.first?.variant == "Fable")
        #expect(windows.first?.usedFraction == 0)
    }

    @Test("Lines without a percentage produce nothing")
    func noFabrication() {
        let text = """
        Current session: unavailable
        Current week (all models): —
        """
        #expect(ClaudeUsageTextParser.windows(from: text, now: t0).isEmpty)
    }

    @Test("Unrecognized output yields no windows at all")
    func garbage() {
        #expect(ClaudeUsageTextParser.windows(from: "Welcome to Claude Code!", now: t0).isEmpty)
    }

    @Test("Print mode's cost summary is not mistaken for usage limits")
    func printModeCostSummaryIsNotUsage() {
        // VERBATIM `result` from `claude -p "/usage" --output-format json`
        // on a real machine. The envelope reported num_turns: 0 — the
        // slash command never ran, and this is just Claude Code's
        // end-of-session cost summary.
        //
        // The trap: it contains the word "Usage" and plenty of numbers.
        // A looser parser would happily report 0% used across the board,
        // which is far worse than reporting nothing — it's a confident
        // lie about how much quota is left.
        let costSummary = """
        Total cost:            $0.0000
        Total duration (API):  0s
        Total duration (wall): 0s
        Total code changes:    0 lines added, 0 lines removed
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write
        """
        #expect(ClaudeUsageTextParser.windows(from: costSummary, now: t0).isEmpty)
    }
}

@Suite("Claude CLI source")
struct ClaudeCLISourceTests {

    private let usageText = """
    Current session: 42% used · resets Jul 23 at 1:59pm (America/Chicago)
    Current week (all models): 18% used · resets Jul 30 at 2:59am (America/Chicago)
    """

    @Test("A JSON envelope's result text is what gets parsed")
    func unwrapsEnvelope() throws {
        let envelope = try #require(
            String(data: JSONEncoder().encode(["result": usageText]), encoding: .utf8)
        )
        let unwrapped = try #require(ClaudeCLI.resultText(fromJSONEnvelope: envelope))
        #expect(unwrapped.contains("42%"))
    }

    @Test("Plain (non-JSON) output still parses")
    func plainOutput() async throws {
        // resultText returns nil for non-JSON; the source treats the raw
        // output as the text.
        #expect(ClaudeCLI.resultText(fromJSONEnvelope: usageText) == nil)

        guard ClaudeCLI.isInstalled else { return }
        let source = ClaudeCLIUsageSource { _ in self.usageText }
        let snapshot = try #require(await source.fetch(now: t0).snapshot)
        #expect(snapshot.windows.count == 2)
    }

    @Test("An always-partial CLI backs off transiently, never fabricating")
    func partialOutputIsTransient() async {
        // A run that never yields limit lines must be a TRANSIENT failure,
        // so the model keeps the last-good data rather than blanking rows.
        guard ClaudeCLI.isInstalled else { return }
        let source = ClaudeCLIUsageSource { _ in "Welcome to Claude Code!" }
        guard case .failed(_, let retry) = await source.fetch(now: t0) else {
            Issue.record("Expected .failed for output with no limit lines"); return
        }
        #expect(retry == .after(5 * 60))
    }
}
