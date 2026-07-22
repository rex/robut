// AppModel.swift — the coordinator. Fetch, record, project, publish.
//
// Deliberately thin: it owns no math (that's PaceEngine) and no parsing
// (that's the sources). It owns *when* things happen and what the UI sees.

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {

    /// Background refresh cadence. Codex reads are local file scans, so
    /// this is cheap; the interval exists to bound Claude's network call,
    /// not to keep up with the filesystem.
    static let refreshInterval: TimeInterval = 2 * 60

    private(set) var states: [Provider: ProviderState] = [:]
    private(set) var verdicts: [String: PaceVerdict] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private let sources: [any UsageSource]
    private let history: UsageHistoryStore
    private var ticker: Task<Void, Never>?

    init(sources: [any UsageSource]? = nil, history: UsageHistoryStore = UsageHistoryStore()) {
        // v1 tracks Codex (zero-auth, local) and Claude (own OAuth).
        self.sources = sources ?? [CodexUsageSource()]
        self.history = history
        for source in self.sources { states[source.provider] = .loading }
    }

    // MARK: - Lifecycle

    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()

        // Sources are independent; a slow one must not delay the others.
        let results = await withTaskGroup(of: (Provider, ProviderState).self) { group in
            for source in sources {
                group.addTask { (source.provider, await source.fetch(now: now)) }
            }
            var collected: [(Provider, ProviderState)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (provider, state) in results {
            states[provider] = state
            if let snapshot = state.snapshot {
                await history.record(snapshot)
            }
        }

        await recomputeVerdicts(now: now)
        lastRefresh = now
    }

    private func recomputeVerdicts(now: Date) async {
        var updated: [String: PaceVerdict] = [:]
        for state in states.values {
            guard let snapshot = state.snapshot else { continue }
            for window in snapshot.windows {
                let samples = await history.samples(for: window.id)
                updated[window.id] = PaceEngine.verdict(window: window, samples: samples, now: now)
            }
        }
        verdicts = updated
    }

    // MARK: - Derived state

    /// Every window Robut currently knows about, worst pace first — this
    /// is the binding constraint, and what the menubar reflects.
    var allWindows: [UsageWindow] {
        states.values
            .compactMap(\.snapshot)
            .flatMap(\.windows)
            .sorted { lhs, rhs in
                let left = verdicts[lhs.id]?.outlook.severity ?? 0
                let right = verdicts[rhs.id]?.outlook.severity ?? 0
                if left != right { return left > right }
                return lhs.kind.order < rhs.kind.order
            }
    }

    var worstOutlook: PaceOutlook? {
        allWindows.compactMap { verdicts[$0.id]?.outlook }
            .max { $0.severity < $1.severity }
    }

    var mood: RobotMood { RobotMood(outlook: worstOutlook) }

    /// Providers in a non-ready state, for the pane's muted footer rows.
    var unavailable: [(provider: Provider, state: ProviderState)] {
        states
            .filter { $0.value.snapshot == nil }
            .map { (provider: $0.key, state: $0.value) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }
}
