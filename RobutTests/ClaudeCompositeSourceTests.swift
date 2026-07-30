// ClaudeCompositeSourceTests.swift — API-first arbitration with the CLI.
//
// The rules under test (ADR-0001): fall back ONLY when the token path
// structurally cannot serve; never on a rate limit; and while the API
// serves, the CLI rides along once per insights interval so the
// analytics block keeps flowing to the stats ledger.

import Foundation
import Testing

@testable import Robut

// MARK: - Composite arbitration

/// A source whose behaviour is entirely scripted, with a call recorder.
private struct ScriptedSource: UsageSource {
    let provider = Provider.claude
    let state: ProviderState
    let calls: LockedBox<Int>

    func fetch(now: Date) async -> ProviderState {
        calls.mutate { $0 += 1 }
        return state
    }
}

@Suite("Claude composite source")
struct ClaudeCompositeSourceTests {

    private func ready() -> ProviderState {
        .ready(UsageSnapshot(
            provider: .claude,
            windows: [makeWindow(used: 0.5, resetsInHours: 3, provider: .claude, kind: .session)],
            sampledAt: t0, planLabel: nil
        ))
    }

    @Test("API serves; the CLI rides along ONCE per insights interval")
    func apiPrimaryWithInsightsRideAlong() async {
        let apiCalls = LockedBox(0)
        let cliCalls = LockedBox(0)
        let composite = ClaudeCompositeSource(
            token: ScriptedSource(state: ready(), calls: apiCalls),
            cli: ScriptedSource(state: ready(), calls: cliCalls)
        )

        guard case .ready = await composite.fetch(now: t0) else {
            Issue.record("expected the API result")
            return
        }
        _ = await composite.fetch(now: t0.addingTimeInterval(120))
        _ = await composite.fetch(now: t0.addingTimeInterval(240))

        #expect(apiCalls.value == 3)
        // First fetch fires the insights ride-along; the next two are
        // inside the hourly interval.
        #expect(cliCalls.value == 1)
    }

    @Test("Sign-in-required hands the job to the CLI")
    func userActionFallsBack() async {
        let composite = ClaudeCompositeSource(
            token: ScriptedSource(
                state: .failed(reason: "Sign in", retry: .userAction), calls: LockedBox(0)
            ),
            cli: ScriptedSource(state: ready(), calls: LockedBox(0))
        )
        guard case .ready = await composite.fetch(now: t0) else {
            Issue.record("expected the CLI to serve")
            return
        }
    }

    @Test("A rate limit does NOT fall back — the CLI hits the same endpoint")
    func rateLimitDoesNotFallBack() async {
        let cliCalls = LockedBox(0)
        let composite = ClaudeCompositeSource(
            token: ScriptedSource(
                state: .failed(reason: "Rate limited", retry: .after(900)), calls: LockedBox(0)
            ),
            cli: ScriptedSource(state: ready(), calls: cliCalls)
        )
        guard case .failed(_, .after) = await composite.fetch(now: t0) else {
            Issue.record("expected the rate limit to surface")
            return
        }
        #expect(cliCalls.value == 0)
    }

    @Test("Fallback CLI failure surfaces the CLI's state, not a sign-in nag")
    func cliFailureSurfacesCLIState() async {
        let composite = ClaudeCompositeSource(
            token: ScriptedSource(
                state: .failed(reason: "Sign in", retry: .userAction), calls: LockedBox(0)
            ),
            cli: ScriptedSource(
                state: .failed(reason: "momentarily unavailable", retry: .after(300)),
                calls: LockedBox(0)
            )
        )
        guard case .failed(let reason, .after) = await composite.fetch(now: t0) else {
            Issue.record("expected the CLI's transient failure")
            return
        }
        #expect(reason == "momentarily unavailable")
    }
}
