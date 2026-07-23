// UsageStatsStore.swift — the statistics ledger: scan, merge, persist.
//
// An actor owning everything the stats domain captures: daily token
// rollups, the hourly token series, the CLI's usage-analytics block,
// prompt activity, Codex plan/credits, and quota estimates. Scanners are
// incremental (cursors persisted with the data), so only the first scan
// pays for the multi-gigabyte backlog. All read-only with respect to
// provider files, all local — nothing leaves the machine.

import Foundation

actor UsageStatsStore {

    /// Full scans are cheap after cursors exist, but there's no reason to
    /// stat thousands of files every 2-minute refresh.
    static let scanInterval: TimeInterval = 10 * 60

    /// Daily rollups are tiny; keep a bounded ~13 months.
    static let dailyRetentionDays = 400
    /// The hourly series only feeds the quota correlation.
    static let hourlyRetentionDays = 21

    private struct State: Codable {
        var daily: [String: DailyRollup] = [:]
        var hourly: [String: TokenTally] = [:]
        var claudeCursors: [String: FileCursor] = [:]
        var codexCursors: [String: FileCursor] = [:]
        var promptCursor = FileCursor()
        var promptsByDay: [String: PromptActivity] = [:]
        var insights: UsageInsights?
        var insightsByDay: [String: InsightsWindow] = [:]
        var codexPlan: CodexPlanInfo?
        var quotaEstimates: [String: QuotaEstimate] = [:]
        var lastScan: Date?
    }

    private var state = State()
    private var loaded = false
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appending(path: "Robut", directoryHint: .isDirectory)
            .appending(path: "usage-stats.json", directoryHint: .notDirectory)
    }

    // MARK: - Scanning

    /// Incremental scan of both transcript stores + prompt history.
    /// Throttled; `force` bypasses the interval (first launch).
    func refreshIfDue(
        claudeRoots: [URL], codexRoots: [URL], promptHistory: URL, now: Date, force: Bool = false
    ) {
        loadIfNeeded()
        if !force, let last = state.lastScan,
           now.timeIntervalSince(last) < Self.scanInterval { return }

        let claude = ClaudeTranscriptScanner.scan(roots: claudeRoots, cursors: state.claudeCursors)
        merge(rollups: claude.rollups, hourly: claude.hourly, provider: .claude)
        state.claudeCursors = claude.cursors

        let codex = CodexRolloutScanner.scan(roots: codexRoots, cursors: state.codexCursors)
        merge(rollups: codex.rollups, hourly: codex.hourly, provider: .codex)
        state.codexCursors = codex.cursors
        if let plan = codex.plan, plan.asOf > (state.codexPlan?.asOf ?? .distantPast) {
            state.codexPlan = plan
        }

        let prompts = PromptHistoryScanner.scan(file: promptHistory, cursor: state.promptCursor)
        for (day, activity) in prompts.byDay {
            var merged = state.promptsByDay[day] ?? PromptActivity()
            merged.prompts += activity.prompts
            merged.sessionIDs.formUnion(activity.sessionIDs)
            merged.projects.formUnion(activity.projects)
            state.promptsByDay[day] = merged
        }
        state.promptCursor = prompts.cursor

        state.lastScan = now
        prune(now: now)
        persist()
    }

    /// The raw `claude /usage` text, forwarded by the CLI source on every
    /// successful fetch — parsed for the analytics block.
    func ingest(usageText: String, at now: Date) {
        loadIfNeeded()
        guard let insights = ClaudeUsageInsightsParser.insights(from: usageText, capturedAt: now)
        else { return }
        state.insights = insights
        // One snapshot of the rolling 24h window per day → a time series.
        if let daily = insights.windows.first(where: { $0.period == "24h" }) {
            state.insightsByDay[StatsScanning.dayKey(now)] = daily
        }
        persist()
    }

    /// Recompute tokens-per-percent for each window's percent series.
    func updateQuotaEstimates(windowSamples: [String: [UsageSample]], now: Date) {
        loadIfNeeded()
        for (windowID, samples) in windowSamples {
            let provider = windowID.split(separator: ".").first.map(String.init) ?? ""
            let hourly = hourlyTokens(provider: provider)
            if let estimate = QuotaEstimator.estimate(
                windowID: windowID, samples: samples, hourlyTokens: hourly, now: now
            ) {
                state.quotaEstimates[windowID] = estimate
            }
        }
        persist()
    }

    // MARK: - Reading

    func snapshot() -> StatsSnapshot {
        loadIfNeeded()
        return StatsSnapshot(
            daily: Array(state.daily.values),
            hourly: state.hourly,
            insights: state.insights,
            insightsByDay: state.insightsByDay,
            promptsByDay: state.promptsByDay,
            codexPlan: state.codexPlan,
            quotaEstimates: state.quotaEstimates,
            lastScan: state.lastScan
        )
    }

    func hourlyTokens(provider: String) -> [Int: TokenTally] {
        loadIfNeeded()
        var result: [Int: TokenTally] = [:]
        let prefix = provider + "|"
        for (key, tally) in state.hourly where key.hasPrefix(prefix) {
            if let hour = Int(key.dropFirst(prefix.count)) { result[hour] = tally }
        }
        return result
    }

    // MARK: - Internals

    private func merge(rollups: [String: DailyRollup], hourly: [Int: TokenTally], provider: Provider) {
        for (key, delta) in rollups {
            var rollup = state.daily[key] ?? delta
            if state.daily[key] != nil {
                rollup.tally += delta.tally
                rollup.messages += delta.messages
                rollup.sidechainMessages += delta.sidechainMessages
            }
            state.daily[key] = rollup
        }
        for (hour, delta) in hourly {
            let key = "\(provider.rawValue)|\(hour)"
            var tally = state.hourly[key] ?? TokenTally()
            tally += delta
            state.hourly[key] = tally
        }
    }

    private func prune(now: Date) {
        let dailyCutoff = StatsScanning.dayKey(
            now.addingTimeInterval(-Double(Self.dailyRetentionDays) * 86_400))
        state.daily = state.daily.filter { $0.value.day >= dailyCutoff }
        state.insightsByDay = state.insightsByDay.filter { $0.key >= dailyCutoff }
        state.promptsByDay = state.promptsByDay.filter { $0.key >= dailyCutoff }

        let hourCutoff = StatsScanning.hourKey(
            now.addingTimeInterval(-Double(Self.hourlyRetentionDays) * 86_400))
        state.hourly = state.hourly.filter { key, _ in
            Int(key.split(separator: "|").last.map(String.init) ?? "") ?? 0 >= hourCutoff
        }
        // Cursors for files that vanished (pruned transcripts) are dead weight.
        state.claudeCursors = state.claudeCursors.filter {
            FileManager.default.fileExists(atPath: $0.key)
        }
        state.codexCursors = state.codexCursors.filter {
            FileManager.default.fileExists(atPath: $0.key)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        state = decoded
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
