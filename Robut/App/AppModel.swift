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
    /// When the in-flight refresh began. Enables a self-healing
    /// single-flight guard: a refresh still "running" past this cap is
    /// presumed wedged and may be superseded, so a hung request can never
    /// permanently block refreshes. The cap sits above the HTTP resource
    /// timeout (`URLSession.robut`, 45s) so a genuinely-working refresh is
    /// never cut off.
    private var refreshStartedAt: Date?
    static let refreshHangCap: TimeInterval = 60

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
        // Claude (Robut's own token, falling back to the CLI when there
        // isn't a usable one — see ClaudeCompositeSource).
        self.sources = sources ?? [CodexUsageSource(), ClaudeCompositeSource()]
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
        let now = Date()
        // Self-healing single-flight. A normal refresh finishes in well
        // under the cap; only a wedged one (e.g. a request stalled across
        // system sleep — the bug that left the spinner stuck and "updated
        // 5h ago") gets superseded.
        if let startedAt = refreshStartedAt, now.timeIntervalSince(startedAt) < Self.refreshHangCap {
            return
        }
        refreshStartedAt = now
        isRefreshing = true
        // Only the CURRENT refresh clears the flags — a superseded,
        // late-returning refresh must not stomp a newer one's state.
        defer { if refreshStartedAt == now { isRefreshing = false; refreshStartedAt = nil } }

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
            applyBackoff(state.retryPolicy, to: provider, at: now)
            // A transient failure (retry `.after`) must not blank real data
            // — a flaky source like the CLI shouldn't make the rows vanish.
            // Keep the last-good snapshot; the "updated Nm ago" footer shows
            // it's aging. `.userAction` and `.notConfigured` DO replace it,
            // because those are states the user needs to see and act on.
            if case .failed(_, .after) = state, states[provider]?.snapshot != nil {
                continue
            }
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

    /// PKCE for the in-flight Claude sign-in. Held only between opening
    /// the browser and pasting the code back; never persisted. Not private
    /// so the sign-in extension (AppModel+ClaudeAuth) can reach it.
    var pendingPKCE: ClaudePKCE?

    /// Providers in a non-ready state, for the pane's muted footer rows.
    var unavailable: [(provider: Provider, state: ProviderState)] {
        states
            .filter { $0.value.snapshot == nil }
            .map { (provider: $0.key, state: $0.value) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }
}
