# TASK_STATE — <feature-name>

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions.
>
> Spec: `specs/<slug>/spec.md` · Plan: `specs/<slug>/plan.md`
> Branch: `main` · Owner: repo maintainer · Last update: 2026-07-22 by Claude Opus 4.8

## 0. TL;DR for a fresh agent session

Building **Robut** — a macOS menubar app showing Claude + Codex usage with
burn-rate projection ("will my current pace last until reset?"). Phase 0
(scaffold + privacy gate) is **done**. **Next action: Slice 1.1** — the
`project.yml` + app skeleton that builds and launches into the menubar.

**Read `AGENTS.md` §1 and §9 before touching anything.** Two hard rules:
this is a **public repo** (no personal data, ever — `make privacy`), and
Robut must **never read another app's keychain item** (that is the exact
bug it exists to fix).

## Standing user directives

<!-- Record durable per-task user directives here. "Continue until blocked",
     "do not wait for my input unless blocked", "skip tests for this slice"
     — anything the maintainer said that should survive compaction.
     PUBLIC REPO: paraphrase directives; never record personal details. -->

- **Autonomy: continue-until-blocked.** Build straight through; stop only on
  a hard blocker or a decision that is the maintainer's to make.
- **Tests are a required gate**, focused on the pace/projection engine.
- **CI is deferred** until the app builds; use `macos-latest` runners when added.
- **Never read another app's keychain item.** Robut owns its own credential.

## 1. Phases

| # | Phase | Status | Exit criteria |
|---|---|---|---|
| 0 | Scaffold + privacy gate | ✅ done | Repo bootstrapped; privacy gate blocking on every commit |
| 1 | Core app + Codex | ✅ done | Builds, launches to menubar, real Codex usage + pace verdict |
| 2 | Claude provider | ⏸ pending | Claude session + weekly windows shown, with zero keychain prompts |
| 3 | Distribution | ⏸ pending | Signed, notarized, Sparkle auto-update, published to Releases |
| 4 | CI | ⏸ pending | `macos-latest` workflow running build + test + lint + privacy |

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices (vertical, atomic, independently mergeable)

### Slice 2.1 — Claude usage via Robut's own OAuth

- Status: ⏸ pending — **the next thing to build**
- Depends on: (none)
- Files (planned): `Robut/Core/Auth/RobutKeychain.swift`,
  `Robut/Core/Auth/ClaudeOAuth.swift`, `Robut/Core/Providers/ClaudeUsageSource.swift`
- Files (do NOT edit): `Robut/Core/Pace/**` (frozen — engine is done and tested)
- Context: endpoint is `https://api.anthropic.com/api/oauth/usage`, called
  with an OAuth access token. PKCE flow, `ASWebAuthenticationSession`.
- Acceptance:
  - [ ] Token is stored in a keychain item **Robut itself creates**, so macOS
        never prompts. Robut must NEVER read `Claude Code-credentials`.
  - [ ] Refresh happens proactively before expiry; a failed refresh degrades
        to a muted row, never a modal.
  - [ ] Session (5h) and weekly windows both surface with pace verdicts.
  - [ ] Tests: response parsing + expiry/refresh logic, synthetic fixtures.
  - [ ] Lint + typecheck + privacy green.

### Slice 2.2 — `claude` CLI probe fallback

- Status: ⏸ pending
- Depends on: Slice 2.1
- Context: spawn `claude` and read `/usage` when OAuth is unavailable. The
  CLI reads its *own* keychain item, so it is silent. Output format is
  unstable — parse defensively and fall back to `.failed` with a short reason.

### Slice 3.1 — Sign, notarize, Sparkle, Releases

- Status: ⏸ pending
- Context: `make signing-init` should write `Local.xcconfig` (gitignored) from
  the Developer ID already in the keychain. Add Sparkle via SPM. Hardened
  Runtime is already on; App Sandbox must stay OFF.

## 3. Blockers / open questions

- (none)

## 4. Recent decisions (append-only, newest first)

- 2026-07-22 — App Sandbox stays OFF. Robut must read `~/.codex` and spawn the
  `claude` CLI; notarization needs Hardened Runtime, not the sandbox.
- 2026-07-22 — Never read another app's keychain item. Robut owns its own
  credential. This is the entire reason the project exists.
- 2026-07-22 — Providers limited to Claude + Codex for v1 (scope restraint).
- 2026-07-22 — Sparkle auto-update is wanted (maintainer is fine with it).

## 5. Next actions (ordered)

1. **Slice 2.1** — Claude usage via Robut's own OAuth (see acceptance above).
2. Slice 2.2 — `claude` CLI probe fallback.
3. Slice 3.1 — signing, notarization, Sparkle, GitHub Releases.
4. Design an app icon from the pixel-robot logo (`AppIcon` is referenced by
   `project.yml` but the asset catalog does not exist yet).
5. Add CI (`macos-latest`: build + test + lint + privacy gate).

## 6. Handoff note (fill when ending a session)

**State:** Robut builds, runs, and works for Codex. Three commits on `main`,
all pushed, all gates green (29 tests / 5 suites, lint clean, privacy clean).

**What works end to end:** menubar robot whose face+colour track worst-case
pace; usage pane leading with the verdict sentence; Codex usage read with zero
credentials from `~/.codex/sessions`; history backfill seeding ~1,500 samples
on first launch so the pace verdict is meaningful immediately.

**Not yet built:** Claude provider (the other half of the value), signing /
notarization / Sparkle, CI, app icon.

**Two traps to not re-introduce:**
1. `.task` on a `MenuBarExtra` label never fires — startup must stay in
   `RobutApp.init`. Symptom is an icon that renders fine and an empty history.
2. Reading `Claude Code-credentials` reintroduces the exact keychain-prompt
   bug this app exists to eliminate. Robut reads only its own item.
