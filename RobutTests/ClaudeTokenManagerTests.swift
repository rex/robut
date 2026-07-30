// ClaudeTokenManagerTests.swift — the single-flight token lifecycle.
//
// The concurrency suite is the reason this file exists: the v0.14 auth
// layer died because two overlapping fetches both spent the same one-shot
// rotating refresh token, and the loser's invalid_grant locked the app
// out (ADR-0001). These tests pin the fix. All values synthetic; no real
// keychain, no network.

import Foundation
import Testing

@testable import Robut

/// Thread-safe recorder for closures that outlive the test's actor.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func mutate(_ change: @Sendable (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&stored)
    }
}

@Suite("Claude token manager")
struct ClaudeTokenManagerTests {

    private func expiredBundle(refreshToken: String? = "old-refresh") -> ClaudeTokenBundle {
        ClaudeTokenBundle(
            accessToken: "stale-access", refreshToken: refreshToken,
            expiresAt: t0, scopes: ["user:inference", "user:profile"]
        )
    }

    private func freshBundle(refreshToken: String? = "rotated-refresh") -> ClaudeTokenBundle {
        ClaudeTokenBundle(
            accessToken: "fresh-access", refreshToken: refreshToken,
            expiresAt: t0.addingTimeInterval(8 * 3600),
            scopes: ["user:inference", "user:profile"]
        )
    }

    private func store(
        _ bundle: ClaudeTokenBundle?, saves: LockedBox<[ClaudeTokenBundle]>? = nil
    ) -> ClaudeTokenStore {
        ClaudeTokenStore(
            load: { bundle },
            save: { saved in saves?.mutate { $0.append(saved) } },
            clear: {}
        )
    }

    // MARK: - The regression that killed v0.14

    @Test("Concurrent callers share ONE refresh — the rotation race is impossible")
    func concurrentRefreshIsSingleFlight() async {
        let calls = LockedBox(0)
        let saves = LockedBox<[ClaudeTokenBundle]>([])
        let fresh = freshBundle()
        let manager = ClaudeTokenManager(
            store: store(expiredBundle(), saves: saves),
            refresher: { _ in
                calls.mutate { $0 += 1 }
                // Long enough that both callers are provably in flight.
                try? await Task.sleep(for: .milliseconds(50))
                return fresh
            }
        )

        async let first = manager.validBundle(now: t0)
        async let second = manager.validBundle(now: t0)
        let outcomes = await [first, second]

        // Exactly one network refresh, and BOTH callers got the result.
        #expect(calls.value == 1)
        for outcome in outcomes {
            guard case .bundle(let bundle) = outcome else {
                Issue.record("expected a bundle, got \(outcome)")
                continue
            }
            #expect(bundle.accessToken == "fresh-access")
            #expect(bundle.refreshToken == "rotated-refresh")
        }
        // The rotated token was persisted before use.
        #expect(saves.value.last?.refreshToken == "rotated-refresh")
    }

    @Test("A response omitting the refresh token carries the old one forward")
    func rotationCarriesOldToken() async {
        let saves = LockedBox<[ClaudeTokenBundle]>([])
        let manager = ClaudeTokenManager(
            store: store(expiredBundle(refreshToken: "keep-me"), saves: saves),
            refresher: { _ in self.freshBundle(refreshToken: nil) }
        )

        let outcome = await manager.validBundle(now: t0)
        guard case .bundle(let bundle) = outcome else {
            Issue.record("expected a bundle, got \(outcome)")
            return
        }
        #expect(bundle.refreshToken == "keep-me")
        #expect(saves.value.last?.refreshToken == "keep-me")
    }

    @Test("A dead refresh token latches sign-in-required; no timer retry")
    func invalidGrantLatches() async {
        let calls = LockedBox(0)
        let manager = ClaudeTokenManager(
            store: store(expiredBundle()),
            refresher: { _ in
                calls.mutate { $0 += 1 }
                throw ClaudeOAuthError.invalidGrant
            }
        )

        guard case .signInRequired = await manager.validBundle(now: t0) else {
            Issue.record("expected signInRequired")
            return
        }
        // The next tick must NOT refresh again — a rejected credential
        // cannot fix itself (the IP-rate-limit lesson).
        guard case .signInRequired = await manager.validBundle(now: t0) else {
            Issue.record("expected signInRequired to latch")
            return
        }
        #expect(calls.value == 1)
    }

    @Test("A transient refresh failure backs off, then tries again")
    func transientFailureRetriesNextTick() async {
        let calls = LockedBox(0)
        let manager = ClaudeTokenManager(
            store: store(expiredBundle()),
            refresher: { _ in
                calls.mutate { $0 += 1 }
                throw ClaudeOAuthError.network
            }
        )

        guard case .transient = await manager.validBundle(now: t0) else {
            Issue.record("expected transient")
            return
        }
        _ = await manager.validBundle(now: t0)
        #expect(calls.value == 2)
    }

    // MARK: - Quiet paths

    @Test("An unexpired token never touches the network")
    func unexpiredSkipsRefresh() async {
        let calls = LockedBox(0)
        let live = freshBundle()
        let manager = ClaudeTokenManager(
            store: store(live),
            refresher: { _ in calls.mutate { $0 += 1 }; return live }
        )

        let outcome = await manager.validBundle(now: t0)
        #expect(outcome == .bundle(live))
        #expect(calls.value == 0)
    }

    @Test("No token, inference-only token, and missing refresh token map to their outcomes")
    func staticOutcomes() async {
        let none = ClaudeTokenManager(store: store(nil), refresher: { _ in self.freshBundle() })
        #expect(await none.validBundle(now: t0) == .noToken)
        #expect(await none.hasToken == false)

        let inferenceOnly = ClaudeTokenBundle(
            accessToken: "a", refreshToken: "r",
            expiresAt: t0.addingTimeInterval(3600), scopes: ["user:inference"]
        )
        let scoped = ClaudeTokenManager(
            store: store(inferenceOnly), refresher: { _ in self.freshBundle() }
        )
        guard case .signInRequired = await scoped.validBundle(now: t0) else {
            Issue.record("inference-only token must require sign-in")
            return
        }

        let unrefreshable = ClaudeTokenManager(
            store: store(expiredBundle(refreshToken: nil)),
            refresher: { _ in self.freshBundle() }
        )
        guard case .signInRequired = await unrefreshable.validBundle(now: t0) else {
            Issue.record("expired without refresh token must require sign-in")
            return
        }
    }

    @Test("Adopt clears the sign-in latch; sign-out clears everything")
    func adoptAndSignOut() async {
        let manager = ClaudeTokenManager(
            store: store(expiredBundle()),
            refresher: { _ in throw ClaudeOAuthError.invalidGrant }
        )
        _ = await manager.validBundle(now: t0)   // latch needsSignIn

        await manager.adopt(freshBundle())
        guard case .bundle = await manager.validBundle(now: t0) else {
            Issue.record("adopt must clear the latch")
            return
        }

        await manager.signOut()
        #expect(await manager.validBundle(now: t0) == .noToken)
    }
}
