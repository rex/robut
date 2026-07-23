// StatsScanning.swift — shared machinery for incremental transcript scans.
//
// The transcript stores are gigabytes of append-only JSONL. Scanning them
// from zero on every refresh would be absurd, so every scanner keeps a
// per-file cursor (byte offset + size + mtime) and reads only appended
// bytes. The first scan is the expensive one; after that a refresh is a
// stat() sweep plus whatever's new.

import Foundation

/// Where a previous scan left off in one file.
struct FileCursor: Sendable, Hashable, Codable {
    var offset: Int64 = 0
    var size: Int64 = 0
    var modified: Double = 0
    /// Codex rollouts report CUMULATIVE totals per session; the last seen
    /// total is needed to turn the next event into a delta.
    var codexLastTotal: TokenTally?
    /// Sticky per-file context discovered earlier in the file.
    var model: String?
    var project: String?
}

enum StatsScanning {

    /// Lines longer than this are skipped — the accounting lines are tiny;
    /// anything huge is content we don't need to parse.
    static let maxLineBytes = 4 * 1024 * 1024

    /// One discovered transcript file with its current size + mtime.
    struct FoundFile: Sendable {
        var url: URL
        var size: Int64
        var modified: Double
    }

    /// Every `*.jsonl` under the roots.
    static func jsonlFiles(under roots: [URL]) -> [FoundFile] {
        var found: [FoundFile] = []
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true
                else { continue }
                found.append(FoundFile(
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0
                ))
            }
        }
        return found
    }

    /// Read complete lines starting at `offset`, invoking `handle` per line.
    /// Returns the new offset (end of the last complete line consumed).
    static func readLines(
        url: URL,
        from offset: Int64,
        handle: (Data) -> Void
    ) -> Int64 {
        guard let file = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? file.close() }
        try? file.seek(toOffset: UInt64(max(0, offset)))

        var consumed = offset
        var carry = Data()
        let newline = UInt8(ascii: "\n")

        while let chunk = try? file.read(upToCount: 1 << 20), !chunk.isEmpty {
            carry.append(chunk)
            while let cut = carry.firstIndex(of: newline) {
                let lineLength = carry.distance(from: carry.startIndex, to: cut)
                if lineLength > 0, lineLength <= maxLineBytes {
                    handle(carry.subdata(in: carry.startIndex..<cut))
                }
                carry.removeSubrange(carry.startIndex...cut)
                consumed += Int64(lineLength) + 1
            }
            // A pathological partial line: drop it rather than balloon.
            if carry.count > maxLineBytes {
                consumed += Int64(carry.count)
                carry.removeAll(keepingCapacity: false)
            }
        }
        return consumed
    }

    /// "2026-07-23" for a date, in the local calendar.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Start-of-hour epoch bucket for a date.
    static func hourKey(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 3600) * 3600
    }

    /// Parse the ISO8601 timestamps both transcript formats use
    /// (with and without fractional seconds).
    static func date(fromISO string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601.year().month().day()
            .timeSeparator(.colon).time(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
    }
}
