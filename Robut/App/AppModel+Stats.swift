// AppModel+Stats.swift — feeding the statistics ledger from the refresh
// loop.
//
// Fire-and-forget by design: the pane must never wait on a transcript
// scan. The store throttles itself (10-minute interval; the first scan is
// the big one), and everything here is read-only against provider files.

import Foundation

@MainActor
extension AppModel {

    /// Kick an incremental stats capture off the refresh path.
    func scheduleStatsCapture(now: Date) {
        // Tests must never scan the real transcript stores.
        guard !AppDelegate.isRunningTests else { return }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let claudeRoots = [home.appending(path: ".claude/projects", directoryHint: .isDirectory)]
        let codexRoots = [
            home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
            home.appending(path: ".codex/archived_sessions", directoryHint: .isDirectory),
        ]
        let promptHistory = home.appending(path: ".claude/history.jsonl", directoryHint: .notDirectory)

        let windowIDs = allWindows.map(\.id)
        let stats = stats
        let history = history

        Task.detached(priority: .utility) {
            await stats.refreshIfDue(
                claudeRoots: claudeRoots,
                codexRoots: codexRoots,
                promptHistory: promptHistory,
                now: now
            )
            // Correlate each window's percent series with the hourly token
            // series — the tokens-per-percent estimate.
            var samples: [String: [UsageSample]] = [:]
            for id in windowIDs {
                samples[id] = await history.samples(for: id)
            }
            await stats.updateQuotaEstimates(windowSamples: samples, now: now)
        }
    }
}
