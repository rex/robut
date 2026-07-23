// PromptHistoryScanner.swift — prompts-per-day from ~/.claude/history.jsonl.
//
// Every prompt the user submits lands there as one line with an
// epoch-millis timestamp, the project path, and a session id — a cheap
// activity series (prompts/day, distinct sessions/day, projects touched)
// without parsing the multi-gigabyte transcripts.

import Foundation

struct PromptScanResult: Sendable {
    var byDay: [String: PromptActivity] = [:]
    var cursor = FileCursor()
}

enum PromptHistoryScanner {

    static func scan(file: URL, cursor: FileCursor) -> PromptScanResult {
        var result = PromptScanResult()
        result.cursor = cursor
        let calendar = Calendar.current

        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if size == result.cursor.size, modified == result.cursor.modified { return result }
        if size < result.cursor.offset { result.cursor.offset = size }

        result.cursor.offset = StatsScanning.readLines(url: file, from: result.cursor.offset) { line in
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let entry = object as? [String: Any],
                  let millis = entry["timestamp"] as? Double
            else { return }
            let stamp = Date(timeIntervalSince1970: millis / 1000)
            let day = StatsScanning.dayKey(stamp, calendar: calendar)

            var activity = result.byDay[day] ?? PromptActivity()
            activity.prompts += 1
            if let session = entry["sessionId"] as? String { activity.sessionIDs.insert(session) }
            if let project = entry["project"] as? String { activity.projects.insert(project) }
            result.byDay[day] = activity
        }
        result.cursor.size = size
        result.cursor.modified = modified
        return result
    }
}
