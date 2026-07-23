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

    @Test("Percentages are read regardless of spacing")
    func percentages() {
        #expect(ClaudeUsageTextParser.percentage(in: "Session: 42%") == 42)
        #expect(ClaudeUsageTextParser.percentage(in: "Session: 42.5 %") == 42.5)
        #expect(ClaudeUsageTextParser.percentage(in: "no numbers here") == nil)
    }

    @Test("Relative reset times are converted to a date")
    func relativeResets() throws {
        let date = try #require(ClaudeUsageTextParser.resetDate(in: "resets in 3h 20m", now: t0))
        #expect(abs(date.timeIntervalSince(t0) - (3 * 3600 + 20 * 60)) < 1)

        let days = try #require(ClaudeUsageTextParser.resetDate(in: "resets in 2d", now: t0))
        #expect(abs(days.timeIntervalSince(t0) - 2 * 86_400) < 1)
    }

    @Test("An unparseable reset is nil rather than a guess")
    func unparseableReset() {
        // An absolute clock time has no timezone here; guessing would be
        // wrong by hours. Nil lets the caller fall back to window length.
        #expect(ClaudeUsageTextParser.resetDate(in: "resets at 3:00 PM", now: t0) == nil)
        #expect(ClaudeUsageTextParser.resetDate(in: "nothing relevant", now: t0) == nil)
    }

    @Test("Session, weekly and Opus lines map to distinct windows")
    func classification() {
        let text = """
        Current session: 42% used, resets in 2h
        This week: 18% used, resets in 4d
        This week (Opus): 5% used, resets in 4d
        """
        let windows = ClaudeUsageTextParser.windows(from: text, now: t0)

        #expect(windows.count == 3)
        #expect(Set(windows.map(\.id)).count == 3)
        #expect(windows.contains { $0.id == "claude.session" })
        #expect(windows.contains { $0.id == "claude.weekly" })
        #expect(windows.contains { $0.id == "claude.weekly.Opus" })
    }

    @Test("An Opus line is not also counted as the general weekly")
    func opusNotDoubleCounted() {
        // "This week (Opus)" contains "week", so keyword order matters.
        let windows = ClaudeUsageTextParser.windows(
            from: "This week (Opus): 5% used", now: t0
        )
        #expect(windows.count == 1)
        #expect(windows.first?.variant == "Opus")
    }

    @Test("Lines without a percentage produce nothing")
    func noFabrication() {
        // The cardinal rule: a missing row is honest, an invented one
        // is not. Never synthesize a window from a label alone.
        let text = """
        Usage
        Current session: unavailable
        This week: —
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

/// Thread-safe "did this run?" flag — the runner closure is `@Sendable`,
/// so a captured `var` can't be mutated from inside it.
private final class CallFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    func set() {
        lock.lock(); defer { lock.unlock() }
        flag = true
    }

    var wasSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
}

@Suite("Claude CLI source and fallback")
struct ClaudeCLISourceTests {

    private let usageText = """
    Current session: 42% used, resets in 2h
    This week: 18% used, resets in 4d
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
        // resultText returns nil for non-JSON; the source falls back to
        // treating the raw output as the text.
        #expect(ClaudeCLI.resultText(fromJSONEnvelope: usageText) == nil)

        let source = ClaudeCLIUsageSource { _ in self.usageText }
        guard ClaudeCLI.isInstalled else { return }
        let snapshot = try #require(await source.fetch(now: t0).snapshot)
        #expect(snapshot.windows.count == 2)
    }

    @Test("Unreadable output fails loudly instead of inventing data")
    func unreadableOutput() async {
        guard ClaudeCLI.isInstalled else { return }
        let source = ClaudeCLIUsageSource { _ in "Welcome to Claude Code!" }
        guard case .failed(_, let retry) = await source.fetch(now: t0) else {
            Issue.record("Expected .failed for unparseable output"); return
        }
        // Backs off hard — re-spawning a CLI on a tight loop is expensive.
        #expect(retry == .after(30 * 60))
    }

    @Test("The composite prefers the token path when it works")
    func prefersToken() async throws {
        let payload = #"{"five_hour":{"utilization":11,"resets_at":1800005000}}"#
        let composite = ClaudeCompositeSource(
            token: ClaudeUsageSource(
                store: syntheticClaudeStore(token: "synthetic"),
                authStatus: { nil },
                session: StubURLProtocol.stub(status: 200, json: payload)
            ),
            cli: ClaudeCLIUsageSource { _ in self.usageText }
        )
        let snapshot = try #require(await composite.fetch(now: t0).snapshot)
        // 11% is the token path's number; the CLI stub says 42%.
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.11) < 0.0001)
    }

    @Test("The composite falls back to the CLI when the token is rejected")
    func fallsBackOnRejectedToken() async throws {
        guard ClaudeCLI.isInstalled else { return }
        let composite = ClaudeCompositeSource(
            token: ClaudeUsageSource(
                store: syntheticClaudeStore(token: "rejected"),
                authStatus: { nil },
                session: StubURLProtocol.stub(status: 401, json: "{}")
            ),
            cli: ClaudeCLIUsageSource { _ in self.usageText }
        )
        let snapshot = try #require(await composite.fetch(now: t0).snapshot)
        #expect(abs((snapshot.windows.first?.usedFraction ?? 0) - 0.42) < 0.0001)
    }

    @Test("The composite does NOT fall back on a rate limit")
    func noFallbackWhileRateLimited() async {
        // This is the important one. The CLI hits the same endpoint, so
        // spawning it during a 429 would be a second way to make the
        // rate limit worse — exactly the mistake that started all this.
        let cliWasCalled = CallFlag()
        let composite = ClaudeCompositeSource(
            token: ClaudeUsageSource(
                store: syntheticClaudeStore(token: "synthetic"),
                authStatus: { nil },
                session: StubURLProtocol.stub(status: 429, json: "{}")
            ),
            cli: ClaudeCLIUsageSource { [usageText] _ in
                cliWasCalled.set()
                return usageText
            }
        )

        let state = await composite.fetch(now: t0)
        #expect(cliWasCalled.wasSet == false)
        guard case .failed(_, let retry) = state else {
            Issue.record("Expected the rate-limited failure to be reported"); return
        }
        #expect(retry == .after(RetryPolicy.defaultRateLimitPause))
    }
}
