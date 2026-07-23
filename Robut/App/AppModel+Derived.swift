// AppModel+Derived.swift — what the UI reads: ordered windows and the
// menubar mood. Split from AppModel to keep that file within the
// architecture line limit.

import Foundation

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
}
