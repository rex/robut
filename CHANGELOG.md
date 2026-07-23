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

## [0.11.0] — 2026-07-23 — Agent: Claude Opus 4.8
### Fixed
- **Robut prompted for the keychain password — the exact bug it exists to
  eliminate.** Cause: local builds were **ad-hoc signed**, whose
  code-signing designated requirement is the build's content hash
  (`cdhash`). Every `make build` produces a new hash, so macOS saw each
  rebuild as a different app and re-prompted for the token item the
  previous build had created. Same mechanism as CodexBar, self-inflicted
  via dev signing.
- Fix: `make signing-init` writes a gitignored `Local.xcconfig` with a
  STABLE identity (Developer ID / Apple Development). The designated
  requirement becomes identity-based (`identifier "com.robut.app" and …
  team`), which is verified stable across rebuilds — so the keychain ACL
  persists and the prompt never recurs. Production is Developer-ID-signed
  and was never affected; this was purely a dev-signing artifact.

### Added
- **All Claude weekly variants.** The response exposes `seven_day` (all
  models), `seven_day_opus`, `seven_day_sonnet`, and
  `seven_day_overage_included` (what CodexBar labels "Fable"). An earlier
  version only read `seven_day_opus`, so the Fable/Sonnet rows were
  missing. Keys + labels read from the Claude Code binary; each present
  variant is now shown. Tests pin all of them.
- A temporary, privacy-safe response-shape log (keys + reset field only,
  no account data — this response carries none) to pin the exact reset
  field from one real poll rather than guessing the wire format again.

### Note
- Known remaining bug, being pinned next: the weekly reset time shows the
  window-length fallback ("7d") instead of the real reset. The shape log
  will reveal the actual reset field/format; a regression test
  (`unixResetHonoured`) already guards the parse. Signing in again (once,
  under the now-stable signature) is needed since the ad-hoc-bound token
  item was deleted.

## [0.10.1] — 2026-07-23 — Agent: Claude Opus 4.8
### Changed
- `AGENTS.md`: record that `setup-token` is inference-only (can't read
  usage) and that provider APIs should be diagnosed offline via `strings`
  on the shipped binary before spending rate-limitable calls.

## [0.10.0] — 2026-07-23 — Agent: Claude Opus 4.8
### Added
- **Full-scope Claude sign-in (PKCE).** Robut now runs the same OAuth flow
  as `claude auth login`, requesting `user:profile` — the scope the usage
  endpoint requires and the one `claude setup-token` intentionally
  withholds. The user authorizes in the browser and pastes the displayed
  code back; Robut exchanges it for a full-scope token stored in its OWN
  keychain item. No keychain-rule violation, no prompts, and it actually
  works.
- **`ClaudeOAuth`** — PKCE (S256), authorize-URL construction, token
  exchange, and refresh. All constants (client id, endpoints, scopes)
  were read from the shipped Claude Code binary via static analysis —
  ZERO network calls — not invented. The client id is a public PKCE
  identifier, not a secret.
- **`ClaudeTokenStore` / `ClaudeTokenBundle`** — the token, refresh token,
  expiry and scopes, persisted as JSON in Robut's own keychain item. A
  `canReadUsage` scope check lets Robut reject an inference-only token
  WITHOUT spending a doomed call on the rate-limited endpoint.
- Proactive refresh: an expired token is refreshed at the token endpoint
  (platform.claude.com) before any usage call, so a fetch never races the
  expiry boundary. A dead refresh token is terminal (`.userAction`),
  never retried on a timer.
- Sign-in UI replacing the setup-token paste: "Sign in with Claude" opens
  the browser; the code comes back via a paste button (no field focus, so
  the menubar panel can't dismiss). 21 new tests (PKCE correctness,
  authorize params, token decoding, expiry, exchange/refresh, and the
  scope guard). 75 tests across 13 suites.

### Changed
- Dropped the guessed `anthropic-beta: oauth-2025-04-20` header — the
  first-party client sends only `Content-Type` on the usage call.
- `ClaudeUsageSource` split (wire format → `ClaudeUsageWire.swift`) and
  `AppModel` split (sign-in → `AppModel+ClaudeAuth.swift`) to stay within
  the architecture line limits.

### Note
- **Root cause of the earlier rejection, proven offline:** `/api/oauth/usage`
  is gated in Claude Code's own code on `user:inference` AND
  `user:profile`; `claude setup-token` is inference-only by design
  ("limited to inference-only for security reasons"). No header or retry
  could ever have fixed it — a full-scope token was always required.
- The sign-in and token endpoints are on platform.claude.com, NOT the
  rate-limited api.anthropic.com/api/oauth/usage. Signing in cannot
  trigger the usage rate limit.

## [0.9.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Fixed
- **`make test` was making live network calls to Anthropic.** A unit-test
  bundle for an app target uses the app itself as its TEST HOST, so
  `xcodebuild test` genuinely LAUNCHES Robut:
  `applicationDidFinishLaunching` fired, the refresh loop started, and
  every single test run hit the provider APIs for real. Roughly a dozen
  runs during development kept an Anthropic rate limit alive that was
  supposed to be expiring — a test suite silently acting as a request
  generator against the user's own account.
  `AppDelegate.isRunningTests` now blocks startup under XCTest (checked
  via `XCTestConfigurationFilePath`, sibling variables, and the
  `XCTestCase` runtime class), with `ROBUT_DISABLE_NETWORK` as a manual
  override and the same variable set on the test scheme for belt and
  braces. Verified by streaming the app's log during a test run: it now
  reports `test host launch — refresh loop NOT started`, and the only
  provider lines are from stubbed `URLProtocol` fakes.

## [0.8.1] — 2026-07-22 — Agent: Claude Opus 4.8
### Changed
- **Print-mode CLI usage confirmed NOT viable.** `claude -p "/usage"
  --output-format json` does not run the slash command: it returns
  `num_turns: 0` and a `result` containing Claude Code's end-of-session
  cost summary. `/usage` appears to be interactive-only, and print mode
  runs a zero-turn session rather than refusing — which is why it looked
  plausible until tried. Recorded at the top of `ClaudeCLIUsageSource`.

### Added
- Regression test pinning the real cost-summary output to **zero**
  windows. That text contains the word "Usage" and many numbers, so a
  looser parser would report 0% used across the board — a confident lie
  about remaining quota, which is worse than reporting nothing. 62 tests.

## [0.8.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Added
- **`ClaudeCLIUsageSource`** — Claude usage with no credential in Robut
  at all. Runs `claude -p "/usage" --output-format json`; Claude Code
  reads its OWN keychain item, so the read is silent. Slower (spawns a
  CLI) and the output format isn't a contract, which is why it's the
  fallback rather than the primary.
- **`ClaudeCompositeSource`** — prefers the token path, falls back to the
  CLI **only** when the token path structurally cannot work (absent or
  rejected credential). It deliberately does NOT fall back on a rate
  limit or server error: the CLI hits the same endpoint, so spawning it
  during a 429 would be a second way to make the problem worse. There's a
  test asserting the CLI is never even invoked while rate limited.
- **`ClaudeUsageTextParser`** — pure text → windows, isolated so that the
  one genuinely uncertain part of this feature lives in a single file.
  Classifies session / weekly / Opus lines, reads percentages, and
  converts relative reset times. Refuses to fabricate: a line without a
  percentage yields no window, and an unparseable reset returns nil
  rather than a guessed timezone.
- `make claude-probe` — captures ONE real sample of the CLI's usage
  output. Exactly one call, so it cannot cause a retry storm.
- 13 tests for the fallback and parser; 61 across 9 suites total.

### Note
- The text parser is **provisional**: it was written without a real
  sample, because verifying it meant calling an endpoint that had just
  rate-limited the machine. Its invariants (never fabricate, never fall
  back while rate limited) are tested and will hold; the exact wording
  cases will need revising once `make claude-probe` produces real output.

## [0.7.1] — 2026-07-22 — Agent: Claude Opus 4.8
### Fixed
- **SwiftLint was never actually gating commits.** `make lint` ran it, but
  `.pre-commit-config.yaml` didn't, so a violation could sail into a
  commit whenever `make lint` wasn't run by hand — which is exactly what
  happened one commit ago. SwiftLint is now a blocking pre-commit hook,
  and the violation it should have caught is fixed.

## [0.7.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Fixed
- **Robut retried a rejected token on every refresh and got the machine
  IP-rate-limited by Anthropic.** A rejected credential cannot fix itself,
  so polling it is not resilience — it is a self-inflicted denial of
  service against the user's own account. Confirmed IP-scoped: the
  endpoint returned 429 to an unauthenticated request from the same
  machine.

### Added
- **`RetryPolicy` on every provider failure** — `.normal`, `.after(_)`, or
  `.userAction`. `AppModel` gates each provider independently: a
  `.userAction` failure is never polled again until the user actually
  changes something (saving a token, clicking Refresh), and `.after`
  honours a `Retry-After` header when the server sends one.
- Anthropic's error `type` (e.g. `authentication_error`) is now surfaced
  in the failure reason and logged, so a rejection is diagnosable instead
  of opaque. Only the type — never the message or body.
- Tests for all of it: 401/403 must yield `.userAction`, 429 must back
  off, `Retry-After` must win over the default pause. 48 tests, 7 suites.

## [0.6.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Fixed
- **Clicking the token field made the whole UI disappear.** The setup UI
  was a `.sheet`, and `MenuBarExtra(.window)` is an NSPanel that closes
  the instant it resigns key — so the sheet taking focus closed the panel
  and took the sheet with it. Compounded by `LSUIElement`: Robut isn't an
  active app and can't readily take keyboard focus for a sheet at all.
  Setup is now rendered **inline** in the pane.

### Changed
- Token entry's primary action is now **"Paste token from clipboard"** —
  one click, no text-field focus required, which is the right shape for a
  menubar panel regardless of the sheet bug. Typing is still available
  behind a disclosure, and the entry is sanity-checked (length, no
  embedded whitespace) without guessing at a token prefix that may change.
- `ClaudeTokenSheet` renamed to `ClaudeSetupView` to match what it is.

## [0.5.1] — 2026-07-22 — Agent: Claude Opus 4.8
### Changed
- `TASK_STATE.md`: Phase 2 marked in-progress — Claude is built and unit
  tested, but the response parser was written from field names and has
  not yet seen a real payload. Records how to diagnose that (keys-only
  logging under subsystem `com.robut.app`, category `providers`).

## [0.5.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Added
- **Claude usage** — the other half of the app. Reads
  `GET https://api.anthropic.com/api/oauth/usage` and surfaces all three
  windows Claude bills against: the 5-hour session limit, the seven-day
  limit, and the separate seven-day **Opus** limit.
- **`RobutKeychain`** — the only keychain surface in the codebase, and it
  touches *only items Robut created*. Reading another app's item is the
  exact bug this project exists to eliminate, so that rule now has one
  enforcing chokepoint rather than being a convention.
- **Token setup via `claude setup-token`** — Anthropic's official way to
  mint a long-lived subscription token. The user runs it once and pastes
  the result into Robut, which stores it in its own keychain item and is
  therefore never prompted again. Deliberately NOT a browser OAuth flow:
  that would mean presenting Claude Code's own OAuth client id from a
  third-party app, and there is no public client registration for
  third-party apps. The sanctioned command is safer and less code.
- **`ClaudeCLI`** — runs `claude auth status --json` to distinguish
  "Claude Code isn't installed", "installed but signed out", and "signed
  in, just needs a token". Only `loggedIn` and `subscriptionType` are
  modelled; the payload's email, org id and org name are deliberately not
  decoded so they cannot later be logged by accident. Has a watchdog that
  terminates the process on timeout, so a wedged CLI can't wedge Robut.
- **`ClaudeTokenSheet`** — one-time setup UI. `SecureField`, copyable
  command, and a Remove option. The token goes straight to the keychain;
  it is never logged, never written to a file, and never redisplayed.
- 11 Claude tests using a stubbed `URLProtocol` and injected keychain/CLI,
  so nothing touches a real credential or spawns a process. 46 tests
  across 7 suites.

### Changed
- **`UsageWindow` gained a `variant`.** Claude bills a general seven-day
  limit *and* a seven-day Opus limit — both `.weekly`, so without a
  discriminator they collided on `id` and would have silently overwritten
  each other's pace history. There's a regression test for it.

### Fixed
- Two Swift 6 `Sendable` violations in the CLI process wrapper: a
  non-`@Sendable` local function captured across queues, and a
  `DispatchWorkItem` captured in a `@Sendable` closure. Both are real
  concurrency faults, not annotation noise. The build is warning-free.

## [0.4.1] — 2026-07-22 — Agent: Claude Opus 4.8
### Changed
- `AGENTS.md` §9: record the menubar traps discovered while making the
  status item appear — `MenuBarExtra` labels are not normal views, app
  lifetime must not rest on SwiftUI `@State`, 0% CPU means blocked rather
  than idle, and bulk history must go through `seed(_:)`. Includes the
  screenshot A/B technique that distinguishes "hidden" from "zero width".

## [0.4.0] — 2026-07-22 — Agent: Claude Opus 4.8
### Fixed
- **Robut was completely invisible in the menubar.** Three separate
  causes, each of which produced the identical symptom — app running,
  no crash, no logs, nothing on screen. Found by screenshotting the
  menubar with the app running and again after quitting it: the images
  were pixel-identical, proving the status item occupied zero width.
  1. A SwiftUI `Canvas` as the `MenuBarExtra` label renders nothing.
     The label backs an `NSStatusItem` rather than appearing in a normal
     view hierarchy, and `Canvas` has no intrinsic size.
  2. Replacing it with `NSImage(size:flipped:drawingHandler:)` failed
     the same way — that initializer is *lazy*, so the image has no
     representation and `Image(nsImage:)` gets nothing. The icon is now
     rasterized into a concrete `NSBitmapImageRep` up front.
  3. `.secondaryLabelColor` cannot resolve when drawing into an
     offscreen bitmap (no `NSAppearance`); the dim tint is now concrete.
- **The refresh loop silently never ran.** The model was created in
  `RobutApp.init()` and parked in `@State`, which does not reliably
  retain it that early — so the ticker's `[weak self]` went nil and the
  loop spun forever doing nothing at 0% CPU. `AppModel.shared` now owns
  the lifetime, and startup runs from `applicationDidFinishLaunching`
  via an `NSApplicationDelegateAdaptor`, which is the only hook a
  menubar-only SwiftUI app can actually rely on.
- **First launch stalled for ~44s.** `seedHistory` looped `record(_:)`
  over 10,000+ backfilled snapshots, and `record` pruned on every call —
  rewriting the whole history file each time. Quadratic disk I/O, which
  read as 0% CPU because it was blocked on the disk. Added
  `UsageHistoryStore.seed(_:)`: merge in memory, prune once, write once.
- **An idle machine reported "unknown" forever.** With no samples in the
  burn-rate lookback the engine had nothing to fit, so it shrugged — even
  though the answer was obvious (7% used, days until reset, untouched for
  two days). `now` is now treated as an observation, since the fetch just
  reported current usage. That makes the flat stretch visible and yields
  the correct `idle` verdict.

### Changed
- Startup refreshes *before* backfilling, so real numbers appear in
  ~2.5s instead of after the seed completes; backfill then enriches pace
  history in the background.
- Codex backfill skips rollout files older than the history retention
  window — every sample from them was discarded immediately afterwards.
- Split `PaceTypes.swift` out of `PaceEngine.swift` to stay within the
  architecture gate's file-length limit.

### Added
- `UsageHistoryStore` test suite: bulk seed of 4,000 snapshots,
  retention pruning, and incremental dedupe (including the guard against
  a stale file rewriting history backwards). 35 tests across 6 suites.
- A `notice`-level log line reporting verdict counts and outlooks — the
  one line that distinguishes "the model is wrong" from "the view is
  wrong" when the menubar looks off. Counts only, nothing identifying.

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
