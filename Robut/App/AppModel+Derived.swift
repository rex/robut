// AppModel+Derived.swift — what the UI reads: ordered windows, provider
// groups, and the menubar mood. Split from AppModel to keep that file
// within the architecture line limit.

import Foundation

/// A provider and all of its windows, with the provider's worst outlook —
/// the unit the pane renders as one titled, badged group.
struct ProviderUsageGroup: Identifiable {
    let provider: Provider
    /// The verdict driving this group's badge — from the LOUDEST window,
    /// alarm-tempered, so a spent session doesn't paint the group red.
    let worstVerdict: PaceVerdict?
    let worstMood: RobotMood
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

    /// The menubar icon's colour: the LOUDEST window, not the worst one.
    /// Those differ, and the difference is the whole point — see
    /// `PaceAlarm`. Folding on raw outlook is what kept the icon red.
    var mood: RobotMood {
        allWindows
            .map { RobotMood(verdict: verdicts[$0.id]) }
            .max { $0.rank < $1.rank } ?? .dim
    }

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
            let driver = loudestWindow(among: windows)
            return ProviderUsageGroup(
                provider: provider,
                worstVerdict: driver.flatMap { verdicts[$0.id] },
                worstMood: windows
                    .map { RobotMood(verdict: verdicts[$0.id]) }
                    .max { $0.rank < $1.rank } ?? .dim,
                windows: windows
            )
        }
    }

    /// The window the icon's colour is coming from — named in the summary.
    /// Loudest first, then worst outlook, so the headline always explains
    /// the colour the user is actually looking at.
    func loudestWindow(among windows: [UsageWindow]) -> UsageWindow? {
        windows.max { lhs, rhs in
            let left = (
                RobotMood(verdict: verdicts[lhs.id]).rank,
                verdicts[lhs.id]?.outlook.severity ?? 0
            )
            let right = (
                RobotMood(verdict: verdicts[rhs.id]).rank,
                verdicts[rhs.id]?.outlook.severity ?? 0
            )
            return left < right
        }
    }

    var worstWindow: UsageWindow? { loudestWindow(among: allWindows) }

    /// The answer-first headline for the whole pane.
    var summaryText: String {
        let window = worstWindow
        return PaceFormatting.summaryText(
            verdict: window.flatMap { verdicts[$0.id] }, window: window
        )
    }
}
