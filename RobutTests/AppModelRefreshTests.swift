// AppModelRefreshTests.swift — the refresh loop survives a hung source.
//
// The loop awaits every fetch, so one fetch that never answers used to
// stop ALL sampling until relaunch (19 hours, 2026-09-04). This pins the
// per-fetch budget. Everything is injected: temp stores, a synthetic
// token store, a source that simply never returns.

import Foundation
import Testing

@testable import Robut

/// Never answers within any test's patience.
private struct HangingSource: UsageSource {
    let provider = Provider.codex

    func fetch(now: Date) async -> ProviderState {
        try? await Task.sleep(for: .seconds(60))
        return .notConfigured
    }
}

@Suite("Refresh loop resilience")
@MainActor
struct AppModelRefreshTests {

    @Test("A fetch that never answers is cut off at the budget, and the loop continues")
    func hungFetchIsBounded() async {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "robut-refresh-\(UUID().uuidString)", directoryHint: .isDirectory)
        let model = AppModel(
            sources: [HangingSource()],
            history: UsageHistoryStore(fileURL: scratch.appending(path: "history.jsonl")),
            stats: UsageStatsStore(fileURL: scratch.appending(path: "stats.json")),
            claudeAuth: ClaudeTokenManager(
                store: syntheticClaudeStore(token: nil),
                refresher: { _ in throw ClaudeOAuthError.network }
            ),
            fetchTimeout: 0.5
        )

        let start = Date()
        await model.refresh()
        #expect(Date().timeIntervalSince(start) < 5)

        // The source is marked as having timed out — a transient failure
        // with a back-off, so the next tick tries again rather than nagging.
        guard case .failed(let reason, .after) = model.states[.codex] else {
            Issue.record("expected a timed-out failure, got \(String(describing: model.states[.codex]))")
            return
        }
        #expect(reason.contains("didn't answer"))
        #expect(model.lastRefresh != nil)
    }
}
