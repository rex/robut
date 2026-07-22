# Changelog

All notable changes to this project are documented here. This project
follows [Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Format:

```markdown
## [X.Y.Z] — YYYY-MM-DD — Agent: <name>
### Added | Changed | Fixed | Removed | Deprecated | Security
- <what changed, in imperative voice>
```

**Every commit requires a version bump and a matching entry here.** The
`scripts/check_version_bumped.py` gate enforces this; `auto-commit.sh`
calls `scripts/bump_version.py <level>` before commit.

**Bump level guidance** (agent decides per slice):
- `patch` — bug fix, documentation change, refactor with no behavior change
- `minor` — new feature, new public API, any backward-compatible addition
- `major` — breaking change, removal, incompatible behavior change

**Agent attribution is required.** Every entry names the agent (or human)
that authored the change. This is how we keep `git blame` honest when
multiple agents and humans work on the same slice.

Append new entries at the top. One entry per commit (same cadence as
version bumps).

---

## [0.3.1] — 2026-07-22 — Agent: Claude Opus 4.8
### Changed
- `TASK_STATE.md`: real phase table, slice definitions for the Claude
  provider and distribution work, decision log, and a handoff note
  naming the two traps worth not re-introducing (`MenuBarExtra` label
  `.task` never fires; never read another app's keychain item).

## [0.3.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Added
- **History backfill.** `UsageSource.backfill()` seeds pace history from
  data the provider already logged locally, so a fresh install answers
  "will I make it?" on first launch instead of reporting "measuring
  pace" for hours — which is exactly the moment someone installs Robut
  wanting an answer. Codex implements it by replaying every historical
  `rate_limits` payload; against a real machine this seeded 1,528
  samples spanning 273 hours. Default implementation returns nothing,
  so providers that can't reconstruct history simply opt out.
- Codex source test suite with synthetic fixtures: latest-payload
  selection, primary + secondary windows, percentage clamping,
  tolerance of malformed lines, and backfill ordering. 29 tests total.

### Fixed
- **The app never actually polled.** Startup was kicked off from a
  `.task` on the `MenuBarExtra` label, which never fires — the label
  backs an `NSStatusItem` rather than appearing in a normal view
  hierarchy. The symptom was an icon that rendered perfectly and a
  history file that stayed empty. Startup now runs from `RobutApp.init`.

## [0.2.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Added
- **The app.** Robut now builds, launches into the menubar, and reports
  real Codex usage. macOS 14+, Swift 6 strict concurrency, SwiftUI
  `MenuBarExtra` with `LSUIElement` (no Dock icon).
- **`PaceEngine`** — the projection engine the app exists for. Estimates
  burn rate by least-squares fit over recent samples (resistant to a
  single spike near the end, unlike last-minus-first), then projects it
  against the reset deadline to answer "do I make it?". Verdicts:
  exhausted / unknown / idle / comfortable / tight / shortfall, each
  carrying the pace ratio, projected exhaustion, and headroom or
  shortfall. Pure and clock-injected, therefore fully testable.
- **`CodexUsageSource`** — Codex usage with zero credentials, read from
  the `rate_limits` payloads Codex already writes to
  `~/.codex/sessions/**/*.jsonl`. No token, no keychain, no network, so
  nothing that can ever prompt.
- **`UsageHistoryStore`** — append-only JSONL sample history in
  Application Support, bucketed by window, pruned at 14 days. Records
  only on change plus a quiet-period heartbeat, so an idle machine
  doesn't bloat the log or flat-line the regression.
- **Robot face menubar icon** — 8×8 pixel art whose colour and
  expression track the worst-case pace across every window (calm green /
  squinting amber / alarmed red / dim when unknown).
- **Usage pane** — one screenful, worst-pace window first, each row
  leading with the verdict sentence rather than a raw percentage.
  Providers that can't be read render as muted rows, never as dialogs.
- 23 tests across 4 suites, covering burn-rate estimation, window
  rollover (a reset must not read as "idle"), every verdict branch, and
  window classification. Fixtures are synthetic; `now` is always injected.

### Changed
- `VIBE.yaml::architecture.exclude_globs` now skips `DerivedData/`,
  `*.xcodeproj/`, and `build/` — Xcode's generated bridging headers are
  not source anyone maintains.
- Privacy gate `--all` now enumerates tracked *and* untracked files and
  fails when it scans zero, instead of reporting a vacuous pass before
  the first commit. History mode scans commit messages and paths only,
  not author identity.

### Fixed
- Swift 6 data race: a shared `ISO8601DateFormatter` static is
  non-Sendable. Replaced with value-type `Date.ISO8601FormatStyle`.

## [0.1.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Added
- Initial project scaffold from `agentic-skeleton` + `lang-swift-apple`.
- Makefile overlaid for the Apple toolchain: `regenerate` / `build` /
  `start` / `dev` / `lint` (SwiftLint) / `typecheck` + `test`
  (xcodebuild), replacing the fail-closed stack stubs.
- `.claude/` config: subagents, slash commands, hooks.
- `specs/_template/` with EARS-notation starter.
- `VERSION` seeded at `0.1.0`; `CHANGELOG.md` in Keep-a-Changelog format.

### Security
- **Privacy gate** (`scripts/check-privacy.sh`) — this repo is public.
  Blocking pre-commit hook scanning staged content and paths for home
  directories, emails, credential prefixes, JWTs, and hardcoded signing
  identities, plus exact strings from a gitignored local denylist.
  Modes: staged (default), `--all`, `--history`.
- `make privacy-init` generates `.privacy-denylist.local` from the local
  machine's identity; the file is gitignored and never committed.
- `VIBE.yaml::privacy` records the public-repo policy; `make validate`
  now runs the privacy gate first.

### Changed
- `VIBE.yaml`: `project.stack: swift-macos-menubar`, tests promoted to
  `required`, autonomy `continue-until-blocked`, Docker marked
  not-applicable, and an `apple:` fragment recording that App Sandbox is
  deliberately OFF (Robut must read `~/.codex` and spawn the `claude`
  CLI; notarization needs Hardened Runtime, not the sandbox).
