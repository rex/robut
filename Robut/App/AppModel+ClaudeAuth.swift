// AppModel+ClaudeAuth.swift — the Claude full-scope sign-in flow.
//
// Split out of AppModel to keep that file focused (and under the
// architecture line limit). The state (`pendingPKCE`) lives on AppModel;
// this is the behaviour around it.
//
// Nothing here logs, echoes, or persists a token value anywhere but
// Robut's own keychain item.

import Foundation

@MainActor
extension AppModel {

    /// Whether Robut holds its own Claude token. Reads its OWN keychain
    /// item, so this never prompts.
    var hasClaudeToken: Bool { ClaudeTokenStore.keychain.load() != nil }

    /// Start sign-in: generate PKCE and return the URL to open in the
    /// browser. The browser displays a code the user pastes back.
    ///
    /// Hits platform.claude.com (authorize), never the rate-limited usage
    /// endpoint — signing in cannot trigger a usage rate limit.
    func beginClaudeSignIn() -> URL? {
        let pkce = ClaudePKCE.generate()
        pendingPKCE = pkce
        return ClaudeOAuth.authorizationURL(pkce: pkce)
    }

    /// Finish sign-in by exchanging the pasted code for a full-scope
    /// token. Returns a user-facing error string on failure, nil on
    /// success.
    func completeClaudeSignIn(pastedCode: String) async -> String? {
        guard let pkce = pendingPKCE else {
            return "Start sign-in again"
        }
        let parsed = ClaudeOAuth.splitPastedCode(pastedCode)
        if let returnedState = parsed.state, returnedState != pkce.state {
            return "That code doesn't match this sign-in — try again"
        }

        do {
            let bundle = try await ClaudeOAuth.exchange(code: parsed.code, pkce: pkce)
            guard bundle.canReadUsage else {
                // Shouldn't happen (we request user:profile), but never
                // store a token that can't do the job.
                return "Sign-in didn't grant usage access — try again"
            }
            ClaudeTokenStore.keychain.save(bundle)
            pendingPKCE = nil
            Log.auth.notice("claude sign-in complete")
            await retryNow()
            return nil
        } catch ClaudeOAuthError.invalidGrant {
            return "That code was already used or expired — sign in again"
        } catch {
            return "Couldn't complete sign-in — try again"
        }
    }

    func signOutClaude() {
        ClaudeTokenStore.keychain.clear()
        pendingPKCE = nil
        Log.auth.notice("claude signed out")
        Task { await retryNow() }
    }
}
