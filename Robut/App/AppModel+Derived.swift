// AppModel+Derived.swift — what the UI reads: ordered windows, provider
// groups, and the menubar mood. Split from AppModel to keep that file
// within the architecture line limit.

import Foundation

/// A provider and all of its windows, with the provider's worst outlook —
/// the unit the pane renders as one titled, badged group.
struct ProviderUsageGroup: Identifiable {
    let provider: Provider
    let worstOutlook: PaceOutlook?
    let windows: [UsageWindow]

    var id: String { provider.rawValue }
}

@MainActor
extension AppModel {

    /// Every window Robut knows about, GROUPED BY PROVIDER — all of one
    /// provider's windows are contiguous rather than interleaved. Providers
    /// are ordered worst-pace first (so one in trouble floats up); within a
    /// provider: session before weekly, then worst-first, then by variant.
    var allWindows: [UsageWindow] {
        let windows = states.values.compactMap(\.snapshot).flatMap(\.windows)

        func severity(_ window: UsageWindow) -> Int {
            verdicts[window.id]?.outlook.severity ?? 0
        }
        var providerWorst: [Provider: Int] = [:]
        for window in windows {
            providerWorst[window.provider] = max(providerWorst[window.provider] ?? 0, severity(window))
        }

        return windows.sorted { lhs, rhs in
            if lhs.provider != rhs.provider {
                let left = providerWorst[lhs.provider] ?? 0
                let right = providerWorst[rhs.provider] ?? 0
                return left != right ? left > right : lhs.provider.rawValue < rhs.provider.rawValue
            }
            if lhs.kind.order != rhs.kind.order { return lhs.kind.order < rhs.kind.order }
            if severity(lhs) != severity(rhs) { return severity(lhs) > severity(rhs) }
            return (lhs.variant ?? "") < (rhs.variant ?? "")
        }
    }

    var worstOutlook: PaceOutlook? {
        allWindows.compactMap { verdicts[$0.id]?.outlook }
            .max { $0.severity < $1.severity }
    }

    var mood: RobotMood { RobotMood(outlook: worstOutlook) }

    /// `allWindows` folded into per-provider groups, preserving order (so the
    /// worst-pace provider stays first, session before weekly within each).
    var providerGroups: [ProviderUsageGroup] {
        var order: [Provider] = []
        var byProvider: [Provider: [UsageWindow]] = [:]
        for window in allWindows {
            if byProvider[window.provider] == nil { order.append(window.provider) }
            byProvider[window.provider, default: []].append(window)
        }
        return order.map { provider in
            let windows = byProvider[provider] ?? []
            let worst = windows
                .compactMap { verdicts[$0.id]?.outlook }
                .max { $0.severity < $1.severity }
            return ProviderUsageGroup(provider: provider, worstOutlook: worst, windows: windows)
        }
    }

    /// The window driving the worst outlook — named in the summary line.
    var worstWindow: UsageWindow? {
        allWindows.max {
            (verdicts[$0.id]?.outlook.severity ?? 0) < (verdicts[$1.id]?.outlook.severity ?? 0)
        }
    }

    /// The answer-first headline for the whole pane.
    var summaryText: String {
        PaceFormatting.summaryText(outlook: worstOutlook, window: worstWindow)
    }
}
