# TASK_STATE — Robut (macOS usage menubar)

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions.
>
> Spec: `specs/<slug>/spec.md` · Plan: `specs/<slug>/plan.md`
> Branch: `main` · Owner: repo maintainer · Last update: 2026-07-23 by Claude Opus 4.8

## 0. TL;DR for a fresh agent session

**Robut** — a macOS menubar app showing Claude + Codex usage with burn-rate
projection ("will my current pace last until reset?"). It is **fully built,
working, and running** (v0.16.0): Codex + Claude both show live usage with
pace verdicts, in a pane **rebuilt to the Robut Design System** — `Theme`
tokens, self-hosted Geist, provider groups, SegmentMeters, an answer-first
summary headline, and the per-bar pace marker.

**Architecture is settled:**
- Codex usage: read from `~/.codex/sessions/**/*.jsonl` (on disk).
- Claude usage: `ClaudeCLIUsageSource` runs `claude -p "/usage"` and parses
  the text (`ClaudeUsageTextParser`). **Robut holds NO credentials** — the
  OAuth/token/keychain layer was built then DELETED (v0.15.0). Do not
  reintroduce it. See `AGENTS.md` §1/§9 and `mem:robut-claude-usage-auth`.
- The pace math lives in `Core/Pace/PaceEngine.swift` (pure, clock-injected,
  heavily tested — this is the product; treat it as load-bearing).

**Current context:** Claude Design delivered the Robut Design System (the
claude.ai design project, synced via the DesignSync tool) and it is now
INTEGRATED — the `Theme` token layer, self-hosted Geist/Geist Mono, the
component views, the rebuilt pane, and the pace marker all shipped in
v0.16.0. Everything green (59 tests, lint, privacy, architecture).

**Next planned work:** distribution (Slice 5.1) and the confirmed low-usage
`.shortfall` fix (§3). Nothing is mid-flight; safe to pause here.

**Read `AGENTS.md` §1 and §9 before touching anything.** This is a **public
repo** — no personal data, ever (`make privacy`; a commit-msg gate scans
messages too). Local dev needs `make signing-init` (stable signing, or the
keychain-prompt bug returns).

## Standing user directives

<!-- Durable per-task directives; PUBLIC REPO: paraphrase, no personal details. -->

- **Autonomy: continue-until-blocked.** Stop only on a hard blocker or a
  decision that's the maintainer's.
- **Tests are a required gate**, focused on the pace/projection engine.
- **Robut holds NO credentials.** Never read any keychain item (not its own,
  not another app's). Codex = disk; Claude = the `claude` CLI, which
  authenticates itself. This is the settled expression of the founding rule.
- **Don't polish the UI right now** — Claude Design owns it. Keep the data
  model clean and correct instead.
- **Diagnose provider formats from real data, not guesses** — capture actual
  output (`claude /usage`, rollout files, the Claude Code binary) before
  writing parsers. Guessing wire formats has cost real time here.
- CI is deferred until requested; use `macos-latest` runners when added.
- Distribution: signed + notarized + GitHub Releases + Sparkle (the
  maintainer is fine with Sparkle).

## 1. Phases

| # | Phase | Status | Exit criteria |
|---|---|---|---|
| 0 | Scaffold + privacy gate | ✅ done | Repo bootstrapped; privacy gate blocking on every commit |
| 1 | Core app + Codex | ✅ done | Builds, launches to menubar, real Codex usage + pace verdict |
| 2 | Claude provider (CLI) | ✅ done | Live Claude usage via `claude /usage`; all windows, correct resets |
| 3 | Design system + pane rebuild | ✅ done | `Theme` + Geist; pane rebuilt to the DS kit (v0.16.0) |
| 4 | Pace marker | ✅ done | Per-bar elapsed-fraction tick on the SegmentMeter |
| 5 | Distribution | ⏸ pending | Signed, notarized, Sparkle auto-update, published to Releases |
| 6 | CI | ⏸ pending | `macos-latest` workflow: build + test + lint + privacy |

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices (vertical, atomic, independently mergeable)

### Slice 4.1 — Pace marker in each progress bar  ✅ DONE

- Status: ✅ done (2026-07-23, v0.16.0). Shipped with the design-system
  integration: `SegmentMeter` draws a 2px tick at
  `window.elapsedFraction(now:)` — the even-pace, land-at-empty-on-reset
  position — in `--text-primary` at 55%.
- **What the maintainer wants:** a marker line on each progress bar showing where
  usage *would* be if consumption were perfectly even across the whole
  window and hit exactly 100% at reset (0 to spare). If the fill is LEFT of
  the marker you're under budget; RIGHT means you're burning too fast.
- **The math is already available — this is the key insight:** the marker
  position is just the **elapsed fraction of the window**:
  `elapsed = (now - window.startedAt) / window.length`
  (clamped 0...1). `UsageWindow.startedAt` = `resetsAt - length` already
  exists (`Core/Models/UsageModels.swift`). No pace-engine change needed;
  it's a pure function of the window + now. (`PaceEngine`'s `safePerHour`
  is the same idea expressed as a rate, if a rate is preferred.)
- Files: `Robut/UI/UsagePane.swift` (`WindowRow` — draw the mark over the
  `ProgressView`, e.g. an overlay at `x = elapsedFraction * width`).
- Acceptance:
  - [x] Marker at elapsed-fraction on every window's bar.
  - [x] Correct at window start (~0), midpoint (~0.5), near reset (~1).
  - [x] Added `elapsedFraction(now:)` to `UsageWindow` + `UsageWindowTests`.
  - [x] Lint + privacy green. `Core/Pace/**` logic untouched.

### Slice 5.1 — Sign, notarize, Sparkle, Releases

- Status: ⏸ pending
- Context: `make signing-init` already writes `Local.xcconfig` (gitignored)
  from the Developer ID. Add Sparkle via SPM. Hardened Runtime is on; App
  Sandbox must stay OFF (Robut reads `~/.codex` and spawns `claude`). No
  app icon asset catalog yet (`AppIcon` referenced but absent) — design it
  from the pixel-robot logo.

## 3. Blockers / open questions

- ~~Low-usage window shows red `.shortfall`~~ **RESOLVED (v0.17.0).** Root
  cause was the 90-minute active slope extrapolated across a multi-day
  horizon (assumes no sleep). Fixed with the two-regime engine — see §4.
- **Watch (v0.17.0):** with thin per-window-id history, long windows read
  "Measuring pace…" until 24h of lived evidence accumulates (seen live on
  Claude Weekly/Fable, whose ids are ~1 day old). Expected to self-resolve.
  If lived pace genuinely stays above sustainable once representative, the
  window CAN go gold/red — that is now a true alarm, not a false one; the
  trailing-72h basis lets anomalous days (e.g. the rate-limit debugging
  marathon) roll out naturally. Tuning knobs live in
  `PaceEngine+LongHorizon.swift` if real weeks show the constants are off.

## 4. Recent decisions (append-only, newest first)

- 2026-07-23 — **Statistics capture layer (v0.18.0).** `Core/Stats/`
  captures everything locally available: daily token rollups (day × provider
  × model × project, incremental cursor scans of both transcript stores),
  the `/usage` analytics block (was discarded), prompt activity, Codex
  plan/credits, an API price table, and the tokens-per-percent quota
  correlation (percent deltas ÷ local hourly tokens → absolute window-size
  estimates). All read-only, all local, fed off the refresh path
  (`AppModel+Stats`), persisted by the `UsageStatsStore` actor. DISPLAY IS
  UNBUILT BY DESIGN — `docs/stats-matrix.md` is the handoff to Claude
  Design (also pushed into the design project); a standalone
  data-exploration window is under consideration.
- 2026-07-23 — **Two-regime pace engine (v0.17.0).** The question "will I
  make it to reset?" is answered differently by horizon: <24h to reset →
  the original 90-min-slope engine (sessions stay sharp); ≥24h → projected
  from the LIVED rate (consumption per wall-clock hour over ≤72h,
  cross-reset — sleep/idle in the denominator), tempered by prior-epoch
  peaks (what past weeks actually consumed; retention now 35d), with red
  gated on ≥24h of lived evidence (else "Measuring pace…"/tight). Files:
  `Core/Pace/PacePattern.swift`, `Core/Pace/PaceEngine+LongHorizon.swift`.
  This surface is the product — the forgiveness model is user-directed.
- 2026-07-23 — **Integrated the Robut Design System** (claude.ai design
  project, via the DesignSync tool). Ported tokens into a Swift `Theme`
  (`Robut/UI/Theme/`), with the four status colours SOURCED FROM
  `RobotMood.nsTint` (not duplicated). Self-hosted Geist + Geist Mono (OFL
  variable fonts, `Robut/Resources/Fonts/`), registered at runtime and
  selected by exact `wght` axis via CoreText. Rebuilt the pane to the DS
  `ui_kits/menubar` kit (summary headline, glow wash, provider groups + badge,
  `SegmentMeter`, per-window verdict) and shipped the pace marker. v0.16.0.
- 2026-07-23 — **Claude data = the `claude` CLI, sole source. OAuth/token/
  keychain layer DELETED** (~1,650 lines). Robut holds no credentials. The
  CLI kept working where OAuth kept breaking on expiry/refresh.
- 2026-07-23 — `claude /usage` output is non-deterministic (~1/3 partial);
  handled by retry (≤4×) + keep-last-good on transient failure.
- 2026-07-23 — Reset display: session relative ("in 4h"), weekly absolute
  ("Thu 3:00 AM"), matching the Claude Code app.
- 2026-07-23 — Windows grouped by provider in the pane.
- 2026-07-23 — Local dev MUST use `make signing-init` (stable signing) or
  ad-hoc rebuilds re-trigger the keychain prompt. Test builds isolated to
  `DerivedData-test/`. Privacy gate now also scans commit messages.
- 2026-07-22 — App Sandbox stays OFF (needs `~/.codex` + `claude`;
  notarization uses Hardened Runtime, not sandbox).
- 2026-07-22 — Providers limited to Claude + Codex for v1.

## 5. Next actions (ordered)

1. **Stats display** — Claude Design has `docs/stats-matrix.md` (also in
   the design project as `stats-matrix.md`); possibly a standalone
   data-exploration window. Build only after their design lands. The data
   is already flowing (`model.stats.snapshot()`).
2. Slice 5.1 — signing, notarization, Sparkle, Releases + app icon (no asset
   catalog yet; `AppIcon` is referenced in `project.yml` but absent).
3. CI (`macos-latest`: build + test + lint + privacy).
4. Watch the long-horizon verdicts over real days (§3) — tune
   `PaceEngine+LongHorizon` constants only against observed weeks.
5. Optional: import the remaining brand PNGs (mascot/wordmark/lockups) into an
   asset catalog for onboarding/marketing surfaces — fonts are already
   vendored, but the PNGs still live only in the design project.

## 6. Handoff note (2026-07-23, v0.16.0)

**State:** Robut is fully built, running, and correct at **v0.16.0** —
Codex (disk) + Claude (CLI) both live, in a pane rebuilt to the Robut Design
System. Working tree committed + pushed, all gates green (59 tests / 10
suites, lint, privacy, architecture, module-rules). Verified live: the pane
renders correctly (provider groups, badges, SegmentMeters + pace marker,
summary headline, glow wash), Geist loads, the menubar item has real width.

**What shipped this session (design-system integration):**
- `Robut/UI/Theme/` — `ColorHex`, `Theme` (colour/metrics/radius/motion),
  `Fonts` (Geist/Geist Mono via CoreText `wght` variation).
- `Robut/UI/Components/` — `SegmentMeter` (+ pace marker), `StatusBadge`.
- `Robut/UI/` — `PaneHeader`, `WindowRowView` (group/window/unavailable),
  rebuilt `UsagePane`.
- Model: `UsageWindow.elapsedFraction(now:)`, `PaceFormatting.summaryText` /
  `badgeLabel`, `AppModel.providerGroups` / `worstWindow` / `summaryText`.
- Fonts vendored at `Robut/Resources/Fonts/` (OFL), registered in
  `AppDelegate`.

**Next:** (1) the CONFIRMED low-usage `.shortfall` fix (§3) — a `Core/Pace`
change, failing test first; (2) Slice 5.1 distribution + app icon; (3) CI.

**Traps not to re-introduce** (all in `AGENTS.md` §9): no keychain/OAuth/token
dependency (Robut holds zero credentials); `make signing-init` before building;
`MenuBarExtra` label can't use `.task`/`Canvas`/lazy-`NSImage` (only `RobotIcon`
bitmap — the menubar item was verified 36×24, not zero-width); `make test` must
not touch the network (guarded); never auto-retry an auth failure. And now: the
four status colours have ONE home — `RobotMood.nsTint`; `Theme.status(_:)`
surfaces them, so never retune them in `Theme`.
