# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: Robut — macOS menubar AI-usage tracker (Swift 6 / SwiftUI /
  xcodegen). Shows Claude + Codex usage with burn-rate projection.
- **Active branch**: `main`
- **Version**: v0.15.0 — fully built, running, all gates green.
- **Active TASK_STATE**: `TASK_STATE.md` — read §0 + §2 Slice 4.1 (next).
- **Last session**: 2026-07-23 (Claude Opus 4.8). Ended by `/compact`.

## Current state (one line)

Working end to end: Codex (read from `~/.codex/sessions`) + Claude (via
`claude -p "/usage"`). **Robut holds NO credentials.** Claude Design is
building the UI in parallel — don't polish visuals.

## Last decisions

- 2026-07-23 Claude = the `claude` CLI, sole source; the OAuth/token/keychain
  layer was built then DELETED (~1,650 lines). Robut holds zero credentials.
- 2026-07-23 Reset display: session relative, weekly absolute; windows
  grouped by provider.
- 2026-07-23 Local dev needs `make signing-init` (stable signing) or the
  keychain prompt returns.

## Open blockers

- None. (Watch item: a low-% window once showed `.shortfall` red during a
  churny debug session — verify it doesn't recur. See TASK_STATE §3.)

## How to resume (for a fresh agent)

1. Read `AGENTS.md` §1/§9, then `TASK_STATE.md` §0 + §2 Slice 4.1.
2. `make signing-init` (once per clone) then `make dev` to run it.
3. `make test` / `make lint` / `make privacy` are the gates.

## Do NOT

- Reintroduce any keychain/OAuth/token dependency — it was deliberately removed.
- Polish the UI — Claude Design owns it right now.
- Change `Core/Pace/**` logic without a test — it's the product.
- Commit personal data (public repo; `make privacy` + a commit-msg gate).
