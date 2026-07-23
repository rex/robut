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
working, and running** (v0.18.0): the pane is on the Robut Design System
(`Theme` tokens, self-hosted Geist, provider groups, SegmentMeters + pace
marker, answer-first summary), the pace engine is TWO regimes (lived-rate
forgiveness for long windows — see §4), and a **statistics capture layer**
(`Core/Stats/`) is live: token rollups, `/usage` analytics, prompt
activity, plan/credits, price table, and tokens-per-percent quota
estimates, all local + read-only, read via `model.stats.snapshot()`.

**Architecture is settled:**
- Codex usage: read from `~/.codex/sessions/**/*.jsonl` (on disk).
- Claude usage: `ClaudeCLIUsageSource` runs `claude -p "/usage"` and parses
  the text (`ClaudeUsageTextParser`). **Robut holds NO credentials** — the
  OAuth/token/keychain layer was built then DELETED (v0.15.0). Do not
  reintroduce it. See `AGENTS.md` §1/§9 and `mem:robut-claude-usage-auth`.
- The pace math lives in `Core/Pace/PaceEngine.swift` (pure, clock-injected,
  heavily tested — this is the product; treat it as load-bearing).

**Current context:** Claude Design is designing the STATS DISPLAY right
now (handoff: `docs/stats-matrix.md`, pushed into the design project as
`stats-matrix.md`; a standalone data-exploration window is on the table).
The data side is done and flowing. Everything green (84 tests / 20
suites, lint, privacy, architecture).

**Next planned work:** build the stats display once Claude Design's
design lands (sync it via the DesignSync tool, same flow as the pane
rebuild); then distribution (Slice 5.1). Nothing is mid-flight; safe to
pause here.

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
| 4.5 | Pace forgiveness | ✅ done | Two-regime engine: lived rate + evidence gate + prior weeks (v0.17.0) |
| 4.7 | Stats capture | ✅ done | `Core/Stats/` ledger — tokens, insights, cost, quota estimates (v0.18.0) |
| 4.8 | Stats display | 🟡 external | Claude Design designing from `docs/stats-matrix.md`; build after |
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

## 6. Handoff note (compaction, 2026-07-23, v0.18.0)

**State:** Robut is fully built, running, and correct at **v0.18.0**.
Working tree clean, all pushed, all gates green (84 tests / 20 suites,
lint, privacy, architecture, module-rules). Three major slices shipped
this session, all verified live:

1. **Design-system integration (v0.16.0)** — `Theme` tokens (status
   colours sourced from `RobotMood.nsTint`), self-hosted Geist/Geist Mono
   (CoreText `wght` axis), pane rebuilt to the DS kit, pace marker.
2. **Two-regime pace engine (v0.17.0)** — <24h to reset: original sharp
   engine; ≥24h: lived rate over ≤72h (`PacePattern.livedRate`, sleep in
   the denominator) + prior-epoch peak learning (retention 35d) + red
   gated on ≥24h evidence. Fixed the 7%-weekly false red — verified live
   (robot went green on the same data). Glow wash now full-height.
3. **Statistics capture (v0.18.0)** — `Core/Stats/`: cursor-incremental
   scanners over both transcript stores, `/usage` analytics parser,
   prompt activity, plan/credits, `PriceTable`, tokens-per-percent quota
   correlator. First live scan captured months of history across both
   providers and produced real quota estimates. Read model:
   `await model.stats.snapshot()`.

**Now:** Claude Design is designing the STATS DISPLAY from
`docs/stats-matrix.md` (also in the design project as `stats-matrix.md`;
a standalone data-exploration window is under consideration). When their
design lands, sync it with the DesignSync tool (list_projects →
"Robut Design System" → read files) exactly like the pane rebuild, and
build the display on `model.stats.snapshot()` + `PriceTable.cost(of:model:)`.

**Watch items:** §3 — long-horizon verdicts over real days (windows read
"Measuring pace…" until their id has 24h of lived history; tune
`PaceEngine+LongHorizon` constants only against observed weeks).

**Traps not to re-introduce** are ALL in `AGENTS.md` §9 — read it. The
newest: the stats layer is read-only + cursor-incremental (never full
rescans, never writes to provider dirs, guarded from `make test`); local
tokens ≠ account usage; Claude tokens live in `usage.iterations`; Codex
`token_count` is cumulative. Plus the standing ones: no keychain/OAuth
(zero credentials), `make signing-init` before building, `MenuBarExtra`
label limits, never auto-retry auth, status colours only in
`RobotMood.nsTint`, pace engine is two regimes — don't unify.

<!-- Older handoffs live in git history; §4 + CHANGELOG carry the facts. -->
