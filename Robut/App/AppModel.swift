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

    /// App-lifetime instance.
    ///
    /// NOT merely a convenience. Creating the model in `RobutApp.init()`
    /// and parking it in `@State` is a lifetime race: SwiftUI does not
    /// reliably retain a `@State` initial value created that early, so
    /// the model could deallocate, the ticker's `[weak self]` would go
    /// nil, and the refresh loop would spin forever doing nothing —
    /// no crash, no logs, 0% CPU, and a permanently grey menubar icon.
    /// Owning it statically makes the lifetime unambiguous.
    static let shared = AppModel()

    private let sources: [any UsageSource]
    private let history: UsageHistoryStore
    private var ticker: Task<Void, Never>?
    private var didSeedHistory = false

    /// Per-provider gate. A provider that just told us "don't ask again
    /// until X" is skipped entirely until X — this is what stops a
    /// rejected credential from being retried on a timer, which is how
    /// Robut previously got this machine IP-rate-limited by Anthropic.
    private var nextFetchAllowed: [Provider: Date] = [:]

    init(sources: [any UsageSource]? = nil, history: UsageHistoryStore = UsageHistoryStore()) {
        // v1 tracks Codex (zero-auth, read from local session files) and
        // Claude (Robut's own token, in Robut's own keychain item).
        self.sources = sources ?? [CodexUsageSource(), ClaudeUsageSource()]
        self.history = history
        for source in self.sources { states[source.provider] = .loading }
    }

    // MARK: - Lifecycle

    func start() {
        guard ticker == nil else { return }
        Log.app.notice("start(): beginning refresh loop")
        // Strong `self` on purpose: this object lives for the lifetime of
        // the app (see `shared`), and a weak capture here previously let
        // the loop silently no-op.
        ticker = Task {
            // Refresh BEFORE seeding. The first refresh is a small read
            // and puts real numbers on screen immediately; backfill scans
            // far more data and takes appreciably longer. Seeding first
            // meant staring at a blank pane and a grey robot until it
            // finished. Pace verdicts sharpen once the seed lands.
            await self.refresh()
            await self.seedHistory()
            await self.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                await self.refresh()
            }
        }
    }

    /// Seed pace history from whatever the providers already logged
    /// locally, so the first launch can answer the question rather than
    /// spending hours accumulating samples first.
    private func seedHistory() async {
        guard !didSeedHistory else { return }
        didSeedHistory = true

        for source in sources {
            let snapshots = await source.backfill()
            guard !snapshots.isEmpty else { continue }
            // Bulk path — see UsageHistoryStore.seed. Looping record()
            // here is what previously stalled first launch for minutes.
            let added = await history.seed(snapshots)
            let message = "\(source.provider.rawValue): seeded \(added) of \(snapshots.count)"
            Log.history.notice("\(message, privacy: .public)")
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

        // Skip anything still in its back-off window. Its previous state
        // stays on screen, so the user keeps seeing why.
        let due = sources.filter { isDue($0.provider, at: now) }
        guard !due.isEmpty else { return }

        // Sources are independent; a slow one must not delay the others.
        let results = await withTaskGroup(of: (Provider, ProviderState).self) { group in
            for source in due {
                group.addTask { (source.provider, await source.fetch(now: now)) }
            }
            var collected: [(Provider, ProviderState)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (provider, state) in results {
            states[provider] = state
            applyBackoff(state.retryPolicy, to: provider, at: now)
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

        // Notice level so it persists to the unified log — this is the
        // one line that tells you whether the model or the view is at
        // fault when the menubar looks wrong. Counts and outlook names
        // only; nothing identifying.
        let summary = updated.values
            .map { String(describing: $0.outlook) }
            .sorted()
            .joined(separator: ",")
        let count = updated.count
        Log.pace.notice(
            "verdicts=\(count, privacy: .public) outlooks=[\(summary, privacy: .public)]"
        )
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

    // MARK: - Back-off

    private func isDue(_ provider: Provider, at now: Date) -> Bool {
        guard let until = nextFetchAllowed[provider] else { return true }
        return now >= until
    }

    private func applyBackoff(_ policy: RetryPolicy, to provider: Provider, at now: Date) {
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

    // MARK: - Claude token

    /// Whether Robut holds a Claude token. Reads its OWN keychain item,
    /// so this never prompts.
    var hasClaudeToken: Bool { RobutKeychain.has(.claudeToken) }

    /// Store a token from `claude setup-token`. The value is never
    /// logged, echoed, or written anywhere but the keychain.
    func saveClaudeToken(_ token: String) {
        do {
            try RobutKeychain.write(token, to: .claudeToken)
            Log.auth.notice("claude token stored")
        } catch {
            Log.auth.error("failed to store claude token")
        }
        // A new token is exactly the user action that clears a
        // `.userAction` back-off.
        Task { await retryNow() }
    }

    func clearClaudeToken() {
        try? RobutKeychain.delete(.claudeToken)
        Log.auth.notice("claude token removed")
        Task { await retryNow() }
    }

    /// Providers in a non-ready state, for the pane's muted footer rows.
    var unavailable: [(provider: Provider, state: ProviderState)] {
        states
            .filter { $0.value.snapshot == nil }
            .map { (provider: $0.key, state: $0.value) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }
}
