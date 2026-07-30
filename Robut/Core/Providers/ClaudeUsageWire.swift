// ClaudeUsageWire.swift — decoding for /api/oauth/usage.
//
// Split out of ClaudeUsageSource to keep that file within the
// architecture line limit. Pure Decodable shapes; no behaviour.
//
// The window keys and their human labels were read from the Claude Code
// binary, verbatim:
//   five_hour                  → "session limit"
//   seven_day                  → "weekly limit"     (all models)
//   seven_day_opus             → "Opus limit"
//   seven_day_sonnet           → "Sonnet limit"
//   seven_day_overage_included → legacy Fable key (kept for back-compat)
//   limits                     → ARRAY of model-scoped windows — the shape
//     that replaced the overage key. Each entry: kind ("weekly_scoped"),
//     percent, resets_at, scope.model.display_name ("Fable"). This is how
//     the Fable weekly arrives today; the CLI's own panel renders it via
//     exactly this filter (`kind === "weekly_scoped"` + display_name).
// A plan may expose any subset; every one that's present is surfaced.

import Foundation

struct UsagePayload: Decodable {
    let fiveHour: Limit?
    let sevenDay: Limit?
    let sevenDayOpus: Limit?
    let sevenDaySonnet: Limit?
    let sevenDayOverage: Limit?
    let limits: [ScopedLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOverage = "seven_day_overage_included"
        case limits
    }

    func windows(provider: Provider, now: Date) -> [UsageWindow] {
        let week = 10_080
        var built: [UsageWindow] = [
            fiveHour?.window(provider: provider, minutes: 300, variant: nil, now: now),
            sevenDay?.window(provider: provider, minutes: week, variant: nil, now: now),
            sevenDayOpus?.window(provider: provider, minutes: week, variant: "Opus", now: now),
            sevenDaySonnet?.window(provider: provider, minutes: week, variant: "Sonnet", now: now),
            sevenDayOverage?.window(provider: provider, minutes: week, variant: "Fable", now: now),
        ].compactMap { $0 }

        // Model-scoped entries. Skip any whose id a legacy key already
        // produced — if the API ever sends both forms for one window,
        // duplicate ids would corrupt the per-window history buckets.
        var seen = Set(built.map(\.id))
        for scoped in limits ?? [] {
            guard let window = scoped.window(provider: provider, now: now),
                  !seen.contains(window.id)
            else { continue }
            seen.insert(window.id)
            built.append(window)
        }
        return built
    }

    /// One entry of the `limits` array. Unknown kinds decode fine and are
    /// simply not rendered — the shape is not a contract.
    struct ScopedLimit: Decodable {
        let kind: String?
        /// Percent-scale, like `utilization` (the CLI maps it 1:1).
        let percent: Double?
        let resetsAt: FlexibleDate?
        let scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }

        struct Scope: Decodable {
            let model: Model?

            struct Model: Decodable {
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                }
            }
        }

        func window(provider: Provider, now: Date) -> UsageWindow? {
            guard kind == "weekly_scoped", let percent else { return nil }
            let length = TimeInterval(7 * 24 * 3600)
            return UsageWindow(
                provider: provider,
                kind: .weekly,
                variant: scope?.model?.displayName,
                usedFraction: min(1, max(0, percent / 100)),
                resetsAt: resetsAt?.date ?? now.addingTimeInterval(length),
                length: length
            )
        }
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
