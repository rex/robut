// ClaudeCLIUsageSource.swift — Claude usage via the CLI, no token at all.
//
// ⛔️ STATUS: NOT VIABLE AS WRITTEN — verified 2026-07-22.
//
// `claude -p "/usage" --output-format json` does NOT run the slash
// command. It returns `num_turns: 0`, `duration_api_ms: 0`, and a
// `result` containing Claude Code's end-of-session cost summary:
//
//     Total cost:            $0.0000
//     Total duration (API):  0s
//     …
//     Usage:                 0 input, 0 output, 0 cache read, 0 cache write
//
// `/usage` appears to be interactive-only. Print mode silently runs a
// zero-turn session instead of refusing, which is why this looked
// plausible until it was actually tried.
//
// Do NOT "fix" this by loosening ClaudeUsageTextParser to read that
// summary — it would report 0% used across the board, which is a
// confident lie about remaining quota. There's a regression test.
//
// Getting usage from the CLI would mean driving the interactive TUI
// through a pseudo-terminal and stripping ANSI, which is a different and
// much larger piece of work. The machinery below (process spawning,
// timeout watchdog, JSON envelope unwrapping, composite arbitration) all
// stays correct and is reusable if that path is ever taken.
//
// Trade-offs vs. the token path (ClaudeUsageSource):
//   + No credential in Robut, nothing to expire, nothing to paste.
//   − Slow: spawns a whole CLI process, seconds not milliseconds.
//   − Output format is not a contract and can change under us.
//
// So this is the FALLBACK, used when the token path can't work. See
// ClaudeCompositeSource for the arbitration.

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

    func fetch(now: Date) async -> ProviderState {
        guard ClaudeCLI.isInstalled else { return .notConfigured }

        guard let output = await run(timeout) else {
            return .failed(
                reason: "Couldn't read usage from the claude CLI",
                retry: .after(10 * 60)
            )
        }

        let text = ClaudeCLI.resultText(fromJSONEnvelope: output) ?? output
        let windows = ClaudeUsageTextParser.windows(from: text, now: now)

        guard !windows.isEmpty else {
            // The parser was written without a real sample, so make the
            // failure diagnosable rather than mysterious. Length only —
            // the body may name projects or accounts.
            Log.providers.notice(
                "claude CLI usage unparsed; chars=\(text.count, privacy: .public)"
            )
            return .failed(
                reason: "Couldn't read the CLI's usage output — run `make claude-probe`",
                retry: .after(30 * 60)
            )
        }

        return .ready(UsageSnapshot(
            provider: provider,
            windows: windows.sorted { $0.kind.order < $1.kind.order },
            sampledAt: now,
            planLabel: nil
        ))
    }
}

// MARK: - Composite

/// Prefers the token path, falls back to the CLI.
///
/// The fallback fires ONLY when the token path structurally cannot work —
/// no token, or one the server rejected. It deliberately does NOT fire on
/// a rate limit or a server error: those mean "ask again later", and
/// spawning a CLI that hits the very same endpoint would just be a second
/// way to make the problem worse.
struct ClaudeCompositeSource: UsageSource {
    let provider = Provider.claude

    let token: ClaudeUsageSource
    let cli: ClaudeCLIUsageSource

    init(
        token: ClaudeUsageSource = ClaudeUsageSource(),
        cli: ClaudeCLIUsageSource = ClaudeCLIUsageSource()
    ) {
        self.token = token
        self.cli = cli
    }

    func fetch(now: Date) async -> ProviderState {
        let primary = await token.fetch(now: now)
        guard shouldFallBack(from: primary) else { return primary }

        let fallback = await cli.fetch(now: now)
        if case .ready = fallback {
            Log.providers.notice("claude: token path unavailable, served by CLI")
            return fallback
        }

        // The CLI didn't help either. Report the PRIMARY failure — it's
        // the actionable one ("add a token"), whereas the CLI's failure
        // is an implementation detail the user can't do anything about.
        return primary
    }

    private func shouldFallBack(from state: ProviderState) -> Bool {
        switch state {
        case .ready:
            false
        case .notConfigured:
            // No token AND Claude Code isn't signed in — nothing to fall
            // back to.
            false
        case .loading:
            false
        case .failed(_, let retry):
            // .userAction means "no usable token". That is exactly the
            // gap the CLI fills. Rate limits and transient errors are not.
            retry == .userAction
        }
    }
}
