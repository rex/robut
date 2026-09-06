# TASK_STATE — Robut (macOS usage menubar)

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions.
>
> Spec: `specs/<slug>/spec.md` · Plan: `specs/<slug>/plan.md`
> Branch: `main` · Owner: repo maintainer · Last update: 2026-09-05 by Claude Fable 5.1

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
- Claude usage (ADR-0001, v0.20–0.21): **API-first** —
  `ClaudeAPIUsageSource` reads `/api/oauth/usage` with Robut's OWN
  full-scope PKCE token (its own keychain item; float resolution; the
  `limits` array carries model-scoped windows like Fable). Token
  lifecycle ONLY in `ClaudeTokenManager` (single-flight actor — the
  v0.14 refresh race is the whole reason it exists). `ClaudeCLIUsageSource`
  is the fallback + hourly insights carrier. **Never read another app's
  keychain item.** See `AGENTS.md` §1/§9, `mem:robut-claude-usage-auth`.
- The pace math lives in `Core/Pace/PaceEngine.swift` (pure, clock-injected,
  heavily tested — this is the product; treat it as load-bearing). Verdict
  severity is alarm-gated (`PaceEngine+Alarm`, v0.19) — outlook is fact,
  alarm is consequence; colour follows the alarm.

**Current context (2026-09-05):** Slice 5.1 — the release pipeline — is
BUILT and dry-run verified (`make export` → universal, Developer ID,
hardened runtime, Sparkle embedded and validated) but NOT yet released:
notarization needs the maintainer's one-time `make notary-init`. The
refresh loop's 19-hour stall (a `waitUntilExit` race) and the "no token"
latch after a keychain failure are fixed (v0.26.0). The menubar robot
is the 16×16 "antenna boxhead" (v0.27.0, the maintainer's pick) and the
app icon ships twice from that one grid — a flat catalog for macOS ≤15
and a Liquid Glass `Robut/AppIcon.icon` that macOS 26 renders natively.
Claude Design is still designing the STATS DISPLAY (`docs/stats-matrix.md`).

**Next planned work:** (1) maintainer runs `make notary-init`, then
`make notarize && make release` for the first tagged release; (2) stats
display once the design lands; (3) re-sync the new robot into the design
project when DesignSync is authorized interactively.

**Read `AGENTS.md` §1 and §9 before touching anything.** This is a **public
repo** — no personal data, ever (`make privacy`; a commit-msg gate scans
messages too). Local dev needs `make signing-init` (stable signing, or the
keychain-prompt bug returns).

## Standing user directives

<!-- Durable per-task directives; PUBLIC REPO: paraphrase, no personal details. -->

- **Autonomy: continue-until-blocked.** Stop only on a hard blocker or a
  decision that's the maintainer's.
- **Tests are a required gate**, focused on the pace/projection engine.
- **Never read another app's keychain item — the founding rule.** Robut
  MAY hold credentials it minted itself, in items it created itself
  (ADR-0001 amended the earlier zero-credential stance; the maintainer
  approved 2026-07-30). All token custody stays in `ClaudeTokenManager`;
  never a second keychain surface; never auto-retry a rejected credential.
- **Claude is the priority; Codex is secondary** (used far less).
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
| 5 | Distribution | 🟡 built | Pipeline + Sparkle shipped (v0.25.0); first release awaits `make notary-init` |
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

- Status: 🟡 built (v0.25.0, 2026-09-05) — awaiting the maintainer's
  one-time `make notary-init`, then `make notarize && make release`.
- Shipped: `make archive/export/notarize/package/appcast/release` +
  `notary-init` / `sparkle-keys-init` / `release-clean`;
  `Config/ExportOptions.template.plist` (Team ID substituted at build);
  Sparkle 2.9.6 (SPM, exact pin), `SUFeedURL` = release asset via
  `releases/latest/download/appcast.xml`, `SUPublicEDKey` in Info.plist;
  updater created after the XCTest guard; "Updates" in the pane footer.
- Dry-run verified: `make export` → universal, Developer ID, hardened
  runtime, timestamped, identity-based DR, Sparkle XPC services valid;
  `spctl` says "Unnotarized Developer ID" — the expected pre-notary state.
- Acceptance (remaining):
  - [ ] `make notarize` → "status: Accepted", stapled, `spctl` accepts.
  - [ ] `make release` → tag `v<VERSION>` + zip + appcast on GitHub.
  - [ ] Install from the zip on a clean account: opens without warning.
  - [ ] Cut a second release; the first install offers the update.
  - [x] App icon — flat catalog + Liquid Glass `AppIcon.icon`, both
        rendered from the 16×16 grid (v0.27.0); actool compiles the
        layered icon into `Assets.car` beside the `.icns` fallback.

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

- 2026-07-30 — **API-first Claude usage; the zero-credential rule amended
  (ADR-0001, v0.20.0–0.21.0).** Forcing function measured on real data:
  under machine load the CLI path delivered 1–3 samples/DAY (07-28/29)
  and blacked out 11 min before a weekly reset; its text also rounds to
  integer percent (~81M tok/step). Post-mortem of the deleted v0.14 layer
  named the real defect — overlapping fetches racing ONE rotating refresh
  token; `invalid_grant` correctly terminal → endless re-sign-in. Fix:
  `ClaudeTokenManager` (actor, single-flight, persist-before-use,
  `.userAction` latch). `ClaudeCompositeSource` arbitrates: API primary,
  CLI only when the token path structurally can't serve, CLI hourly for
  the insights text. Wire: `/api/oauth/usage` now carries model-scoped
  windows ONLY in a `limits` array (kind `weekly_scoped`, `percent`,
  `scope.model.display_name`) — decoded with id continuity
  (`claude.weekly.Fable`); shape proven offline from the binary
  (`fetchUtilization`, `NPt`, `formatRateLimits` — floats floored for
  display). Founding rule intact: never another app's keychain item.
- 2026-07-30 — **First fully-witnessed weekly close.** Reset captured at
  03:00:28 (92→94% final climb, then 0%); Fable 76%→1%. This epoch seeds
  `priorEpochPeaks` (the quality gate had excluded last week's thin
  4-sample record) and calibrates the quota estimator. Left on the table
  ~6-8%.
- 2026-07-26 — **Alarm ≠ outlook (v0.19.0).** `PaceAlarm` separates "what
  happens" from "how loudly": alert requires dry ≥6h AND ≥25% of time
  left. Replayed on real history: 52% red / 0% gold became 48/45/7.
  Colour follows the alarm (`RobotMood(verdict:)`); per-row prose became
  the meter's `PaceProjection` marker + tooltip.
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

1. **First release (maintainer).** `make notary-init` once — it asks
   for your Apple ID email and an APP-SPECIFIC PASSWORD (account.apple.com
   → Sign-In and Security → App-Specific Passwords); the Team ID comes
   from `Local.xcconfig`. Then `make notarize && make release`. The
   first `make release` in a terminal asks Keychain to let
   `generate_appcast` read the Sparkle key — click Always Allow. Verify
   `spctl --assess --type execute build/release/export/Robut.app` says
   "Notarized Developer ID", then install the zip from the GitHub
   Release on a clean user account.
2. **Brand sync.** The 16×16 antenna boxhead shipped (v0.27.0); the
   design project still carries the 8×8 (`components/brand/RobotFace.jsx`,
   `guidelines/brand-robot-moods.html`, the marks). Push the new grids
   and the icon renders there — DesignSync needs an interactive
   `/design-login` first.
3. **Stats display** — Claude Design has `docs/stats-matrix.md`; build
   only after their design lands (`model.stats.snapshot()` is flowing).
4. CI (`macos-latest`: build + test + lint + privacy) — deferred until
   requested; the release targets are manual by design.
5. Watch the long-horizon verdicts over real weeks (§3). With 2-minute
   API sampling restored, prior-epoch learning finally has clean input;
   re-tune `PaceEngine+Alarm` / `+LongHorizon` only against replayed
   history.

## 6. Handoff note (2026-09-05, v0.26.x)

**State:** working tree clean, all pushed, all gates green (lint,
typecheck, privacy, architecture, module-rules, version-gate; test suite
"Test Succeeded" — the xcpretty summary no longer prints a count).

**Shipped this session:** skeleton sync to v0.48.0 (v0.24.0); the release
pipeline + Sparkle (v0.25.0, `c89f469`); the refresh-loop resilience
fix (v0.26.0, `47ac34c`).

**Load-bearing facts for whoever picks this up:**
- `make notarize` = archive → export → notarize → staple into
  `build/release/`; `make release` = package → appcast → tag →
  `gh release create`. Guards: `archive` refuses without a Team ID in
  `Local.xcconfig`; `package` refuses an un-stapled app; `appcast` fails
  without `sparkle:edSignature`. `make export` was dry-run verified:
  universal, hardened runtime, timestamped, identity-based designated
  requirement, Sparkle's XPC services validated.
- Sparkle feed = `https://github.com/rex/robut/releases/latest/download/appcast.xml`
  (release asset). `SUPublicEDKey` is in `Info.plist`; the private key
  is in the maintainer's login keychain (a pre-existing Sparkle key was
  found there and reused). `generate_appcast` silently writes an
  UNSIGNED appcast if the archived app's public key is missing — the
  scratch test proved it, hence the guard.
- The 19-hour stall: `ClaudeCLI.run` parked in `waitUntilExit` with no
  child (Foundation loses the exit notification when `terminate()` races
  the child's exit). Runner rebuilt on the termination handler;
  `AppModel.bounded` budgets every fetch (4 min); `RobutKeychain.read`
  throws on failure and the manager retries instead of latching.
- The running app before this session had been on CLI fallback since
  09-01 (keychain read failed at a launchd-outage launch; last token
  rotation 08-26). After relaunch the manager retries the keychain; if
  the Aug-26 refresh token is dead the footer reads "Claude · sign in
  again" and the maintainer reconnects via the pane.
- Icon: NOT shipped. Any icon must come from the new 16×16 glyph.

Older handoffs live in git history; §4 + CHANGELOG carry the facts.
