// UsageSource.swift — the contract every provider implements.
//
// Sources never throw at the caller and never surface UI. They return a
// ProviderState, including the failure cases, because "this provider is
// unavailable" must render as a muted row — never as an interruption.

import Foundation

protocol UsageSource: Sendable {
    var provider: Provider { get }

    /// Read current usage. Must not block indefinitely and must not
    /// prompt the user for anything, ever.
    func fetch(now: Date) async -> ProviderState

    /// Historical snapshots to seed pace history at startup, oldest first.
    ///
    /// Optional. A source that can reconstruct the past (because the
    /// provider already logged it locally) should implement this, so a
    /// fresh install can answer "will I make it?" immediately instead of
    /// reporting "measuring pace" for hours.
    func backfill() async -> [UsageSnapshot]
}

extension UsageSource {
    /// Most providers can't reconstruct history; that's fine.
    func backfill() async -> [UsageSnapshot] { [] }

    /// Standard home-relative path resolution, overridable in tests.
    static func homeDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
