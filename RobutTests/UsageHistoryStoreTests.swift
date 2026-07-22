// UsageHistoryStoreTests.swift — history persistence and bulk ingest.
//
// Every case uses a throwaway file in the temp directory. PUBLIC REPO:
// never point these at the real Application Support store.

import Foundation
import Testing

@testable import Robut

@Suite("Usage history store")
struct UsageHistoryStoreTests {

    private func tempStore() -> (UsageHistoryStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "robut-history-\(UUID().uuidString).jsonl", directoryHint: .notDirectory)
        return (UsageHistoryStore(fileURL: url), url)
    }

    private func snapshot(
        at: Date, used: Double, kind: UsageWindow.Kind = .weekly
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(
                provider: .codex, kind: kind, usedFraction: used,
                resetsAt: at.addingTimeInterval(48 * 3600), length: 168 * 3600
            )],
            sampledAt: at,
            planLabel: nil
        )
    }

    @Test("Bulk seed ingests a large history and persists it once")
    func bulkSeed() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // Deliberately large: looping record() over this many is what
        // stalled first launch for minutes with the app at 0% CPU.
        let start = Date().addingTimeInterval(-10 * 24 * 3600)
        let snapshots = (0..<4000).map { step in
            snapshot(at: start.addingTimeInterval(Double(step) * 120),
                     used: Double(step) / 4000)
        }

        let added = await store.seed(snapshots)
        #expect(added > 3000)

        let samples = await store.samples(for: "codex.weekly")
        #expect(samples.count == added)
        // Persisted, and readable back by a fresh store over the same file.
        let reopened = UsageHistoryStore(fileURL: url)
        #expect(await reopened.samples(for: "codex.weekly").count == added)
    }

    @Test("Seed drops samples older than the retention window")
    func seedPrunes() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let ancient = Date().addingTimeInterval(-40 * 24 * 3600)
        let recent = Date().addingTimeInterval(-2 * 3600)
        let added = await store.seed([
            snapshot(at: ancient, used: 0.10),
            snapshot(at: ancient.addingTimeInterval(3600), used: 0.20),
            snapshot(at: recent, used: 0.30),
        ])
        #expect(added == 3)

        // Only the in-retention sample survives.
        let samples = await store.samples(for: "codex.weekly")
        #expect(samples.count == 1)
        #expect(abs((samples.first?.usedFraction ?? 0) - 0.30) < 0.0001)
    }

    @Test("Incremental record keeps changes and skips flat duplicates")
    func recordDeduplicates() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let base = Date().addingTimeInterval(-3600)
        await store.record(snapshot(at: base, used: 0.10))
        // Same value moments later — a heartbeat isn't due yet, so skip.
        await store.record(snapshot(at: base.addingTimeInterval(60), used: 0.10))
        // Value moved — always interesting.
        await store.record(snapshot(at: base.addingTimeInterval(120), used: 0.15))
        // Backwards in time — a stale file must never rewrite history.
        await store.record(snapshot(at: base.addingTimeInterval(-600), used: 0.99))

        let samples = await store.samples(for: "codex.weekly")
        #expect(samples.count == 2)
        #expect(samples.map(\.usedFraction) == [0.10, 0.15])
    }
}
