// ClaudeCLIUsageSource.swift — Claude usage via the CLI, no token at all.
//
// Runs `claude -p "/usage" --output-format json`. Claude Code reads its
// OWN keychain item, so the read is silent — the prompt only ever
// happens when a *different* app reads that item, which Robut never does.
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
