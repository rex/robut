// ClaudeUsageWire.swift — decoding for /api/oauth/usage.
//
// Split out of ClaudeUsageSource to keep that file within the
// architecture line limit. Pure Decodable shapes; no behaviour.

import Foundation

// MARK: - Wire format

struct UsagePayload: Decodable {
    let fiveHour: Limit?
    let sevenDay: Limit?
    let sevenDayOpus: Limit?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }

    func windows(provider: Provider, now: Date) -> [UsageWindow] {
        [
            fiveHour?.window(provider: provider, minutes: 300, variant: nil, now: now),
            sevenDay?.window(provider: provider, minutes: 10_080, variant: nil, now: now),
            sevenDayOpus?.window(provider: provider, minutes: 10_080, variant: "Opus", now: now),
        ].compactMap { $0 }
    }

    struct Limit: Decodable {
        let utilization: Double?
        let utilizationPercent: Double?
        let resetsAt: FlexibleDate?

        enum CodingKeys: String, CodingKey {
            case utilization
            case utilizationPercent = "utilization_percent"
            case resetsAt = "resets_at"
        }

        func window(
            provider: Provider, minutes: Int, variant: String?, now: Date
        ) -> UsageWindow? {
            guard let percent = utilization ?? utilizationPercent else { return nil }
            let length = TimeInterval(minutes * 60)
            return UsageWindow(
                provider: provider,
                kind: UsageWindow.Kind(windowMinutes: minutes),
                variant: variant,
                usedFraction: min(1, max(0, percent / 100)),
                resetsAt: resetsAt?.date ?? now.addingTimeInterval(length),
                length: length
            )
        }
    }
}

/// `resets_at` has appeared as both a unix timestamp and an ISO-8601
/// string across versions. Accept either rather than break on a change.
struct FlexibleDate: Decodable {
    let date: Date

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds)
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = ISO8601.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format"
            )
        }
        date = parsed
    }
}
