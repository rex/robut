# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: Robut — macOS menubar AI-usage tracker (Swift 6 / SwiftUI /
  xcodegen). Shows Claude + Codex usage with burn-rate projection.
- **Active branch**: `main`
- **Version**: v0.18.0 — statistics capture layer; all gates green (84 tests).
- **Active TASK_STATE**: `TASK_STATE.md` — read §0 then §5 (next).
- **Last session**: 2026-07-23 (Claude Opus 4.8). Ended by `/compact`.
  Shipped design-system integration, pace forgiveness, stats capture.

## Current state (one line)

Working end to end: Codex (from `~/.codex/sessions`) + Claude (via
`claude -p "/usage"`). **Robut holds NO credentials.** The pane is now rebuilt
to the Robut Design System — `Theme` tokens, self-hosted Geist, provider
groups, SegmentMeters, an answer-first summary, and the per-bar pace marker.

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
- 2026-07-23 Claude = the `claude` CLI, sole source; OAuth/token/keychain
  layer was built then DELETED (~1,650 lines). Robut holds zero credentials.

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

- Reintroduce any keychain/OAuth/token dependency — it was deliberately removed.
- Change `Core/Pace/**` logic without a test — it's the product.
- Retune the four status colours anywhere but `RobotMood.nsTint` — `Theme`
  sources them from there on purpose.
- Commit personal data (public repo; `make privacy` + a commit-msg gate).
