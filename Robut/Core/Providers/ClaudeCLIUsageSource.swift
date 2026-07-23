// ClaudeCLIUsageSource.swift — Claude usage via the CLI, no token at all.
//
// `claude -p "/usage" --output-format json` returns the usage report as
// text ("Current session: 3% used · resets Jul 23 at 2pm …") — parsed by
// ClaudeUsageTextParser. It reads Claude Code's OWN auth, so it's silent;
// Robut holds no credential of its own on this path.
//
// IMPORTANT — it is NON-DETERMINISTIC: a given call returns the full
// report only ~2 of 3 times, otherwise a partial output with no limit
// lines (an earlier investigation mistook that partial output for the
// command being "not viable"). So `fetch` retries a few times, and a run
// that never yields limit lines returns a TRANSIENT failure so the model
// keeps the last-good data rather than blanking the rows.
//
// Do NOT loosen ClaudeUsageTextParser to read the cost-summary variant —
// it would report 0% across the board, a confident lie about remaining
// quota. There's a regression test.
//
// Trade-offs vs. a token/JSON approach (tried, then removed — it kept
// breaking on OAuth expiry/refresh):
//   + No credential in Robut, nothing to expire, nothing to sign into.
//   − Slow: spawns a whole CLI process, seconds not milliseconds.
//   − Text output is not a contract and can change under us.
//
// This is the SOLE Claude source: Robut holds no Claude credential at all
// (the CLI reads Claude Code's own auth), which is the cleanest possible
// alignment with the rule that Robut never reads another app's keychain —
// it reads none.

import Foundation

struct ClaudeCLIUsageSource: UsageSource {
    let provider = Provider.claude

    /// Generous: this spawns a Node CLI that talks to the network.
    static let defaultTimeout: TimeInterval = 45

    /// Injectable so tests never spawn a process.
    let run: @Sendable (TimeInterval) async -> String?
    let timeout: TimeInterval

    init(
        timeout: TimeInterval = defaultTimeout,
        run: (@Sendable (TimeInterval) async -> String?)? = nil
    ) {
        self.timeout = timeout
        self.run = run ?? { seconds in
            await ClaudeCLI.usageOutput(timeout: seconds)
        }
    }

    /// `claude /usage` is non-deterministic: a given call returns the full
    /// usage report only ~2 out of 3 times, otherwise a partial output with
    /// no limit lines. So try a few times before giving up.
    static let maxAttempts = 4

    func fetch(now: Date) async -> ProviderState {
        guard ClaudeCLI.isInstalled else { return .notConfigured }

        for attempt in 1...Self.maxAttempts {
            guard let output = await run(timeout) else { continue }
            let text = ClaudeCLI.resultText(fromJSONEnvelope: output) ?? output
            let windows = ClaudeUsageTextParser.windows(from: text, now: now)
            if !windows.isEmpty {
                return .ready(UsageSnapshot(
                    provider: provider,
                    windows: windows.sorted { $0.kind.order < $1.kind.order },
                    sampledAt: now,
                    planLabel: nil
                ))
            }
            let summary = "attempt \(attempt), \(text.count) chars"
            Log.providers.notice("claude CLI usage unparsed: \(summary, privacy: .public)")
        }

        // Every attempt came back without limit lines. Keep the last-good
        // data on screen (a short back-off) rather than blanking the rows.
        return .failed(
            reason: "Claude usage momentarily unavailable",
            retry: .after(5 * 60)
        )
    }
}
