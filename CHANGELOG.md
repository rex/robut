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
