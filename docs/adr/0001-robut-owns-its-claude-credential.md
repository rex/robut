---
status: accepted
date: 2026-07-30
deciders: "maintainer"
consulted: "agent (Claude)"
informed: "—"
tags: [auth, providers, reliability]
---

# ADR-0001: Robut holds its own Claude credential (amends the zero-credential rule)

## Context and Problem Statement

Robut's Claude source spawns `claude -p "/usage"` and parses text. That
path was chosen (and the OAuth layer deleted, v0.15.0) because "the token
path kept breaking on expiry/refresh" while the CLI "worked reliably with
retries." Three weeks of production use falsified the second half: the
CLI call is non-deterministic (~2/3 success), takes seconds, and under
real machine load (several concurrent agent sessions) its failure rate
compounds with Robut's retry/backoff machinery into *hour-scale sampling
gaps*. Measured 2026-07-28/29: one and three samples per DAY against a
2-minute design cadence, plus an 11-minute blackout in the final hour
before a weekly reset — the single most important measurement moment the
app has. Separately, the text output rounds to integer percent (~81M
tokens per step on the observed weekly window), discarding most of the
resolution the pace engine could use.

Post-mortem of the deleted layer (git `26e078c^`) found the actual
defect: **no synchronization around token refresh.** The refresh loop
provably produces overlapping fetches (the sleep-wedge supersede guard,
`d043930`); two concurrent fetches both spent the same one-shot rotating
refresh token; the loser's `invalid_grant` was — correctly — treated as
terminal, demanding a fresh sign-in. "Kept breaking on expiry/refresh"
was a self-inflicted race, not an API property.

## Decision Drivers

- The pace engine is the product; its input cadence and resolution were
  silently degraded for days with no alarm.
- The API (`/api/oauth/usage`) serves float utilization, epoch resets,
  and more windows (`seven_day_opus`, `_sonnet`, `_overage_included`)
  in one bounded ~sub-second call.
- The founding rule must survive: **never read another app's keychain
  item** (that is the CodexBar disease this app exists to cure).
- A rejected credential must never be retried on a timer (IP-rate-limit
  incident, `1fceb61`).

## Considered Options

1. **Keep CLI-only** and harden the retry pipeline.
2. **OAuth PKCE token in Robut's own keychain item; CLI as fallback**
   (resurrect v0.14 layer with the race fixed).
3. Statusline-hook tee (Claude Code writes rate_limits JSON per prompt).

## Decision Outcome

**Option 2.** The CLI's failure modes are inherent (process spawn,
non-determinism, integer text); the token path's one real defect has a
named fix. Option 3 mutates Claude Code's configuration, breaking
Robut's read-only posture toward provider state.

The zero-credential rule is **amended, not repealed**: Robut may hold
credentials **it minted itself, in keychain items it created itself**
(`RobutKeychain`, service `com.robut.app.tokens`). Reading any other
app's item — above all `Claude Code-credentials` — remains forbidden.
An app is never prompted for an item it created, and stable signing
(`make signing-init`, `106b098`) keeps the ACL stable across rebuilds.

### Consequences

- Float-resolution, deterministic 2-minute sampling; richer windows;
  the whole CLI retry/backoff pile-up dissolves out of the hot path.
- The CLI source remains: fallback whenever the token path structurally
  cannot serve, and the hourly carrier for the `/usage` analytics block
  (insights exist only in the text).
- New invariants (enforced in code + tests):
  1. **Single-flight refresh** — `ClaudeTokenManager` (actor) is the only
     component that reads, refreshes, or writes the token. Concurrent
     callers share one in-flight refresh; the rotated bundle is persisted
     before first use.
  2. `invalid_grant` → `.userAction`, never timer-retried (unchanged).
  3. Sign-in/refresh hit `platform.claude.com`, never the rate-limited
     usage endpoint.
  4. An inference-only token is rejected by scope inspection, without
     spending a call.
- Contributors building without a signing identity get ad-hoc builds
  whose keychain item re-prompts across rebuilds; the CLI fallback keeps
  the app functional without ever connecting a token.
