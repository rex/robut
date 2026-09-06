# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: Robut — macOS menubar AI-usage tracker (Swift 6 / SwiftUI /
  xcodegen). Shows Claude + Codex usage with burn-rate projection.
- **Active branch**: `main`
- **Version**: v0.27.0 — release pipeline + Sparkle; loop-stall fixed;
  16×16 robot + Liquid Glass icon; all gates green.
- **Active TASK_STATE**: `TASK_STATE.md` — read §0 then §5 (next).
- **Last session**: 2026-09-05 (Claude Fable 5.1). Skeleton sync; Slice
  5.1 (Developer ID export, notarization + Sparkle targets, appcast as
  a release asset) dry-run verified up to the notary gate; diagnosed and
  fixed the 19h refresh-loop stall + the keychain "no token" latch;
  16×16 robot candidates rendered for the maintainer's pick.

## Current state (one line)

Working end to end: Codex (from `~/.codex/sessions`) + Claude **API-first**
(`/api/oauth/usage`, Robut's OWN token, single-flight refresh; CLI
fallback + hourly insights). Pane on the Robut Design System with
alarm-gated colour and the projection marker.

## Last decisions

- 2026-07-23 **Statistics capture layer** (v0.18.0): `Core/Stats/` scans
  both transcript stores incrementally into a local ledger — daily token
  rollups, `/usage` analytics, prompt activity, plan/credits, price table,
  and tokens-per-percent quota estimates. Display UNBUILT — the handoff is
  `docs/stats-matrix.md` (also in the design project). Read model:
  `model.stats.snapshot()`.
- 2026-07-23 **Two-regime pace engine** (v0.17.0): <24h to reset = original
  sharp engine; ≥24h = LIVED rate over ≤72h (sleep/idle in the denominator)
  + prior-epoch peak learning (retention 35d) + red gated on ≥24h evidence.
  Fixed the 7%-weekly false red; glow wash now spans the full pane.
- 2026-07-23 Integrated the Robut Design System (claude.ai design project):
  a Swift `Theme` (status colours sourced from `RobotMood.nsTint`), self-hosted
  Geist/Geist Mono, and a full pane rebuild + the pace marker. v0.16.0.
- 2026-09-05 **Release = zip + Sparkle appcast as GitHub Release assets**
  (feed `releases/latest/download/appcast.xml`); `make notarize` then
  `make release`; every release signed with the same Developer ID;
  `archive` refuses ad-hoc, `package` refuses un-stapled, `appcast`
  refuses unsigned.
- 2026-09-06 **The robot is the 16×16 antenna boxhead** (maintainer's
  pick; the 8×8 was an agent's shortcut). One grid drives the menubar,
  the pane, the flat icon catalog, AND a Liquid Glass `AppIcon.icon`
  (two glass layers on a dark gradient) — `Scripts/render-app-icon.swift`
  renders both; xcodegen types the document `wrapper.icon`.
- 2026-09-05 **The loop must never await an unbounded fetch**: runner
  rebuilt around the termination handler; `AppModel.bounded` budgets
  every fetch; keychain read failures retry instead of latching.
- 2026-07-30 **API-first Claude (ADR-0001)**: the CLI sampler collapsed
  under load (1–3 samples/day; blackout before a reset), so the OAuth
  layer returned with its killer fixed — `ClaudeTokenManager`, a
  single-flight actor (the v0.14 "kept breaking on refresh" was a
  concurrent-refresh race on a rotating token). Robut's token lives in
  Robut's OWN keychain item; another app's item is still never read.
- 2026-07-23 Claude = the `claude` CLI, sole source; OAuth/token/keychain
  layer deleted (~1,650 lines) — superseded 07-30 by ADR-0001 above.

## Open blockers

- None. (Watch: long windows read "Measuring pace…" until their id has 24h
  of lived history; verify verdicts over real days — TASK_STATE §3.)

## How to resume (for a fresh agent)

1. Read `AGENTS.md` §1/§9, then `TASK_STATE.md` §0 + §6 (handoff) + §5.
2. `make signing-init` (once per clone) then `make dev` to run it.
3. `make test` / `make lint` / `make privacy` are the gates.
4. Stats display work: read `docs/stats-matrix.md`, then sync Claude
   Design's work via the DesignSync tool ("Robut Design System" project).

## Do NOT

- Read another app's keychain item, ever. Robut's own token is touched
  ONLY by `ClaudeTokenManager` — never add a second keychain surface.
- Change `Core/Pace/**` logic without a test — it's the product.
- Retune the four status colours anywhere but `RobotMood.nsTint` — `Theme`
  sources them from there on purpose.
- Commit personal data (public repo; `make privacy` + a commit-msg gate).
