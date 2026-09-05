// AppModel+Fetching.swift — the fetch budget and the per-provider gates.
//
// Split from AppModel to keep that file focused (and under the
// architecture line limit). Two rules live here, both learned the hard
// way: no fetch may hold the loop past its budget, and a provider that
// said "don't ask" is not asked.

import Foundation

@MainActor
extension AppModel {

    /// A fetch that cannot outlive its budget. The loop awaits every
    /// source, so a single hung fetch — a CLI spawn whose exit
    /// notification Foundation lost, 2026-09-04 — stopped ALL sampling
    /// for 19 hours until relaunch. The fetch keeps running in its own
    /// task if it ignores the deadline; its late result is discarded.
    /// One leaked task beats a dead loop.
    static func bounded(
        _ source: any UsageSource, now: Date, timeout: TimeInterval
    ) async -> ProviderState {
        let resumed = AtomicFlag()
        return await withCheckedContinuation { continuation in
            let finish: @Sendable (ProviderState) -> Void = { state in
                guard resumed.testAndSet() == false else { return }
                continuation.resume(returning: state)
            }
            Task { finish(await source.fetch(now: now)) }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                finish(.failed(
                    reason: "\(source.provider.displayName) didn't answer within \(Int(timeout / 60))m",
                    retry: .after(5 * 60)
                ))
            }
        }
    }

    // MARK: - Back-off

    func isDue(_ provider: Provider, at now: Date) -> Bool {
        guard let until = nextFetchAllowed[provider] else { return true }
        return now >= until
    }

    func applyBackoff(_ policy: RetryPolicy, to provider: Provider, at now: Date) {
        switch policy {
        case .normal:
            nextFetchAllowed[provider] = nil
        case .after(let pause):
            nextFetchAllowed[provider] = now.addingTimeInterval(pause)
        case .userAction:
            // Only an explicit user action clears this. Retrying a
            // rejected credential on a timer is a self-inflicted DoS.
            nextFetchAllowed[provider] = .distantFuture
        }
    }

    /// Clear every gate and refresh now. Only ever called from a genuine
    /// user action (the Refresh button, saving a token).
    func retryNow() async {
        nextFetchAllowed.removeAll()
        await refresh()
    }

    /// Providers in a non-ready state, for the pane's muted footer rows.
    var unavailable: [(provider: Provider, state: ProviderState)] {
        states
            .filter { $0.value.snapshot == nil }
            .map { (provider: $0.key, state: $0.value) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }
}
