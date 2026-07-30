// ClaudeTokenManager.swift — the ONLY component that touches the token.
//
// THE FIX FOR WHAT KILLED THE v0.14 AUTH LAYER (see ADR-0001): the old
// code refreshed from inside `fetch()`, unsynchronized. The refresh loop
// provably produces overlapping fetches (the sleep-wedge supersede
// guard), so two fetches would both spend the same ONE-SHOT rotating
// refresh token. The loser's `invalid_grant` was — correctly — terminal,
// and the app demanded a fresh sign-in. Over and over. "Kept breaking on
// expiry/refresh" was that race.
//
// This actor makes the race impossible by construction:
//   • one cached bundle, loaded once, all writes serialized here;
//   • ONE refresh in flight ever — concurrent callers await the same
//     task and share its outcome;
//   • the rotated bundle is persisted BEFORE anyone uses it, so a crash
//     mid-refresh can lose at most the access token, never the refresh
//     token's continuity;
//   • a dead refresh token flips `needsSignIn` and stays terminal until
//     the user acts (never retried on a timer — the IP-rate-limit rule).

import Foundation

actor ClaudeTokenManager {

    /// What a caller may do next. `PaceVerdict`-style: outcome + policy,
    /// so the source never invents retry behaviour of its own.
    enum Outcome: Sendable, Equatable {
        /// Use this bundle now.
        case bundle(ClaudeTokenBundle)
        /// No token exists — offer sign-in, fall back to the CLI.
        case noToken
        /// Only a fresh sign-in can help. Maps to `.userAction`.
        case signInRequired(String)
        /// A blip (network, 5xx). Maps to a short back-off.
        case transient(String)
    }

    private let store: ClaudeTokenStore
    private let refresher: @Sendable (String) async throws -> ClaudeTokenBundle

    private var cached: ClaudeTokenBundle?
    private var loaded = false
    private var needsSignIn = false
    private var inFlight: Task<ClaudeTokenBundle, any Error>?

    init(
        store: ClaudeTokenStore = .keychain,
        refresher: @escaping @Sendable (String) async throws -> ClaudeTokenBundle = {
            try await ClaudeOAuth.refresh(refreshToken: $0)
        }
    ) {
        self.store = store
        self.refresher = refresher
    }

    // MARK: - Reads

    /// Whether a token exists at all (valid or not). Reads Robut's OWN
    /// keychain item, so this never prompts.
    var hasToken: Bool {
        loadIfNeeded()
        return cached != nil
    }

    /// A usable bundle, refreshing first if needed. Single-flight: any
    /// number of concurrent callers produce at most ONE network refresh.
    func validBundle(now: Date) async -> Outcome {
        loadIfNeeded()
        guard let bundle = cached else { return .noToken }
        if needsSignIn {
            return .signInRequired("Sign in again to show Claude usage")
        }
        // Scope check BEFORE any network: an inference-only token cannot
        // read usage, and no refresh will change its scopes.
        guard bundle.canReadUsage else {
            return .signInRequired("Sign in again — this token can't read usage")
        }
        guard bundle.isExpired(now: now) else { return .bundle(bundle) }
        guard let refreshToken = bundle.refreshToken else {
            needsSignIn = true
            return .signInRequired("Session expired — sign in again")
        }

        let task = inFlight ?? Task { [refresher] in
            try await refresher(refreshToken)
        }
        inFlight = task

        do {
            let fresh = try await task.value
            // Actor reentrancy: several callers can resume here with the
            // same result. The merge is deterministic, so repeated save +
            // cache of identical values is harmless.
            let carried = ClaudeTokenBundle(
                accessToken: fresh.accessToken,
                // Rotation: some responses omit a new refresh token; the
                // old one then remains valid and is carried forward.
                refreshToken: fresh.refreshToken ?? bundle.refreshToken,
                expiresAt: fresh.expiresAt,
                scopes: fresh.scopes.isEmpty ? bundle.scopes : fresh.scopes
            )
            store.save(carried)          // persist BEFORE first use
            cached = carried
            inFlight = nil
            Log.auth.notice("claude token refreshed")
            return .bundle(carried)
        } catch ClaudeOAuthError.invalidGrant {
            inFlight = nil
            needsSignIn = true
            Log.auth.notice("claude refresh token rejected — sign-in required")
            return .signInRequired("Session expired — sign in again")
        } catch {
            inFlight = nil
            return .transient("Couldn't refresh the Claude session")
        }
    }

    // MARK: - Writes (sign-in / sign-out)

    /// Adopt a bundle from a completed sign-in.
    func adopt(_ bundle: ClaudeTokenBundle) {
        store.save(bundle)
        cached = bundle
        loaded = true
        needsSignIn = false
        inFlight?.cancel()
        inFlight = nil
    }

    func signOut() {
        store.clear()
        cached = nil
        loaded = true
        needsSignIn = false
        inFlight?.cancel()
        inFlight = nil
    }

    // MARK: - Private

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        cached = store.load()
    }
}
