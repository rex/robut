# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: Robut — macOS menubar AI-usage tracker (Swift 6 / SwiftUI /
  xcodegen). Shows Claude + Codex usage with burn-rate projection.
- **Active branch**: `main`
- **Version**: v0.16.0 — design system integrated; all gates green.
- **Active TASK_STATE**: `TASK_STATE.md` — read §0 then §5 (next).
- **Last session**: 2026-07-23 (Claude Opus 4.8). Design-system integration.

## Current state (one line)

Working end to end: Codex (from `~/.codex/sessions`) + Claude (via
`claude -p "/usage"`). **Robut holds NO credentials.** The pane is now rebuilt
to the Robut Design System — `Theme` tokens, self-hosted Geist, provider
groups, SegmentMeters, an answer-first summary, and the per-bar pace marker.

## Last decisions

- 2026-07-23 Integrated the Robut Design System (claude.ai design project):
  a Swift `Theme` (status colours sourced from `RobotMood.nsTint`), self-hosted
  Geist/Geist Mono, and a full pane rebuild + the pace marker. v0.16.0.
- 2026-07-23 Claude = the `claude` CLI, sole source; OAuth/token/keychain
  layer was built then DELETED (~1,650 lines). Robut holds zero credentials.
- 2026-07-23 Local dev needs `make signing-init` (stable signing) or the
  keychain prompt returns.

## Open blockers

- **Confirmed:** a LOW-usage window shows red `.shortfall` — seen live at
  Claude Weekly 7% → "Runs dry ~1d 20h early" with `<1%/hr` rates. It's a
  pace-engine projection artifact at tiny rates, NOT the new UI. See
  TASK_STATE §3; fixing it touches `Core/Pace` and needs a test.

## How to resume (for a fresh agent)

1. Read `AGENTS.md` §1/§9, then `TASK_STATE.md` §0 + §5.
2. `make signing-init` (once per clone) then `make dev` to run it.
3. `make test` / `make lint` / `make privacy` are the gates.

## Do NOT

- Reintroduce any keychain/OAuth/token dependency — it was deliberately removed.
- Change `Core/Pace/**` logic without a test — it's the product.
- Retune the four status colours anywhere but `RobotMood.nsTint` — `Theme`
  sources them from there on purpose.
- Commit personal data (public repo; `make privacy` + a commit-msg gate).
