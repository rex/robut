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
working, and running** (v0.15.0): Codex + Claude both show live usage with
pace verdicts, grouped by provider, with absolute weekly reset times.

**Architecture is settled:**
- Codex usage: read from `~/.codex/sessions/**/*.jsonl` (on disk).
- Claude usage: `ClaudeCLIUsageSource` runs `claude -p "/usage"` and parses
  the text (`ClaudeUsageTextParser`). **Robut holds NO credentials** — the
  OAuth/token/keychain layer was built then DELETED (v0.15.0). Do not
  reintroduce it. See `AGENTS.md` §1/§9 and `mem:robut-claude-usage-auth`.
- The pace math lives in `Core/Pace/PaceEngine.swift` (pure, clock-injected,
  heavily tested — this is the product; treat it as load-bearing).

**Current context:** Claude Design is working on the UI in parallel — so
DON'T invest in visual polish; keep the data layer clean and correct for
their handoff. Working tree clean, everything pushed. Everything green
(51 tests, lint, privacy, architecture).

**Next planned work:** the "pace marker" feature — see §5. Nothing is
mid-flight; safe to pause here.

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
| 3 | UI polish | 🟡 external | Claude Design is doing this in parallel — don't duplicate |
| 4 | Pace marker | ⏸ pending | Per-bar "on-budget" line (see §2 Slice 4.1) |
| 5 | Distribution | ⏸ pending | Signed, notarized, Sparkle auto-update, published to Releases |
| 6 | CI | ⏸ pending | `macos-latest` workflow: build + test + lint + privacy |

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices (vertical, atomic, independently mergeable)

### Slice 4.1 — Pace marker in each progress bar  ← NEXT

- Status: ⏸ pending (requested 2026-07-23). Coordinate with Claude Design —
  they own the visual; this slice provides the value + a simple mark.
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
  - [ ] Marker at elapsed-fraction on every window's bar.
  - [ ] Correct at window start (~0), midpoint (~0.5), near reset (~1).
  - [ ] Add `elapsedFraction(now:)` (or similar) to `UsageWindow` + a test.
  - [ ] Lint + privacy green. Don't touch `Core/Pace/**` logic.

### Slice 5.1 — Sign, notarize, Sparkle, Releases

- Status: ⏸ pending
- Context: `make signing-init` already writes `Local.xcconfig` (gitignored)
  from the Developer ID. Add Sparkle via SPM. Hardened Runtime is on; App
  Sandbox must stay OFF (Robut reads `~/.codex` and spawns `claude`). No
  app icon asset catalog yet (`AppIcon` referenced but absent) — design it
  from the pixel-robot logo.

## 3. Blockers / open questions

- **Watch:** a window occasionally computed `.shortfall` (red) at LOW usage
  during the churny debug session. Likely a transient pace-history artifact
  (dozens of relaunches + changing window set), but VERIFY over a normal day
  that a low-% window never shows red. If it persists, look at
  `PaceEngine.burnRate` fitting against the real `UsageHistoryStore` samples.

## 4. Recent decisions (append-only, newest first)

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

1. **Slice 4.1 — pace marker** (the math is trivial; see §2). Coordinate
   with Claude Design so the mark fits their visual.
2. Slice 5.1 — signing, notarization, Sparkle, Releases + app icon.
3. CI (`macos-latest`: build + test + lint + privacy).
4. Investigate the low-usage `.shortfall` sighting (§3) if it recurs.

## 6. Handoff note (compaction, 2026-07-23)

**State:** Robut is fully built, running, and correct at **v0.15.0** —
Codex (disk) + Claude (CLI) both live, grouped by provider, absolute weekly
resets, Fable/Sonnet/Opus windows. Working tree clean, all pushed, all gates
green (51 tests / 9 suites, lint, privacy, architecture).

**Now:** Claude Design is building the UI in parallel — do NOT polish
visuals; keep the data model clean. Next coding work is the **pace marker**
(§2 Slice 4.1) — a pure function of the window (elapsed fraction), no engine
change. Nothing is mid-flight; the pause is safe.

**Traps not to re-introduce** (all in `AGENTS.md` §9): no keychain
dependency (Robut holds zero credentials now); `make signing-init` before
building or the keychain prompt returns; `MenuBarExtra` label can't use
`.task`/`Canvas`/lazy-`NSImage`; `make test` must not run the app on the
network (guarded); never auto-retry an auth failure; bounded timeouts so a
sleep-stalled request can't wedge the loop.

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
