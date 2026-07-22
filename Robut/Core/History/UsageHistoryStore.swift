// UsageHistoryStore.swift — the sample history the pace engine reads.
//
// A snapshot alone can't tell you your burn rate; you need the same window
// observed over time. This is that record: an append-only JSONL log in
// Application Support, bucketed by window id, pruned by age.
//
// An actor because it's touched from the refresh task and the UI, and
// Swift 6 will not let that be sloppy.

import Foundation

actor UsageHistoryStore {

    /// Samples older than this are dropped. Two weeks comfortably covers a
    /// 7-day window plus the previous one for context.
    static let retention: TimeInterval = 14 * 24 * 3600

    /// Don't record a sample if usage hasn't moved and the last one is
    /// recent — otherwise an idle machine writes a line every minute
    /// forever and the regression gets a long flat tail.
    static let minQuietInterval: TimeInterval = 10 * 60

    private let fileURL: URL
    private var samples: [String: [UsageSample]] = [:]
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appending(path: "Robut", directoryHint: .isDirectory)
            .appending(path: "usage-history.jsonl", directoryHint: .notDirectory)
    }

    // MARK: - Reading

    func samples(for windowID: String) -> [UsageSample] {
        loadIfNeeded()
        return samples[windowID] ?? []
    }

    // MARK: - Writing

    /// Record every window in a snapshot. Returns the ids actually written.
    @discardableResult
    func record(_ snapshot: UsageSnapshot) -> [String] {
        loadIfNeeded()
        var written: [String] = []

        for window in snapshot.windows {
            let sample = UsageSample(at: snapshot.sampledAt, usedFraction: window.usedFraction)
            guard shouldRecord(sample, for: window.id) else { continue }
            samples[window.id, default: []].append(sample)
            append(sample, windowID: window.id)
            written.append(window.id)
        }

        prune()
        return written
    }

    private func shouldRecord(_ sample: UsageSample, for windowID: String) -> Bool {
        guard let last = samples[windowID]?.last else { return true }
        // Never record backwards — a stale file can report an old sample.
        guard sample.at > last.at else { return false }
        // Usage moved: always interesting.
        if abs(sample.usedFraction - last.usedFraction) > 1e-9 { return true }
        // Flat: only keep a heartbeat, so idle still reads as idle.
        return sample.at.timeIntervalSince(last.at) >= Self.minQuietInterval
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let handle = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in handle.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let row = try? decoder.decode(Row.self, from: data)
            else { continue }
            samples[row.window, default: []].append(UsageSample(at: row.at, usedFraction: row.used))
        }
        for key in samples.keys {
            samples[key]?.sort { $0.at < $1.at }
        }
        prune()
    }

    private func append(_ sample: UsageSample, windowID: String) {
        let row = Row(window: windowID, at: sample.at, used: sample.usedFraction)
        guard let data = try? JSONEncoder().encode(row),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
    }

    /// Drop aged-out samples from memory, and rewrite the file when it has
    /// drifted meaningfully from what we hold.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        var removed = 0
        for (key, values) in samples {
            let kept = values.filter { $0.at >= cutoff }
            removed += values.count - kept.count
            samples[key] = kept.isEmpty ? nil : kept
        }
        if removed > 0 { rewrite() }
    }

    private func rewrite() {
        let encoder = JSONEncoder()
        let rows = samples
            .flatMap { window, values in
                values.map { Row(window: window, at: $0.at, used: $0.usedFraction) }
            }
            .sorted { $0.at < $1.at }

        let text = rows
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data((text + "\n").utf8).write(to: fileURL, options: .atomic)
    }

    /// Compact on-disk shape. Short keys because this file grows forever-ish.
    private struct Row: Codable {
        let window: String
        let at: Date
        let used: Double

        enum CodingKeys: String, CodingKey {
            case window = "w"
            case at = "t"
            case used = "u"
        }
    }
}
