<div align="center">

# Robut

**AI usage in your menubar — that just works, and never asks for your keychain password.**

</div>

---

Robut is a macOS menubar app that shows how much of your Claude and Codex
usage you have left, and — the part nobody else gets right — **whether your
current burn rate will actually last until the next reset.**

Click the robot. See where you stand. Get on with your day.

## Why this exists

Every other tool in this space reads *Claude Code's* keychain item to get an
access token. macOS binds each keychain item to a list of trusted apps, and
Claude Code **rewrites that item every time it refreshes its token** — which
resets the trust list. So the other app falls out of it, and macOS prompts
you for your password. Again. And again. Forever.

It's not a bug anyone can patch from the outside. It's structural.

Robut sidesteps it entirely, on a simple principle:

> **Hold no credentials at all.**

- **Codex** usage is already on disk, written by Codex itself, in
  `~/.codex/sessions/`. Robut just reads it.
- **Claude** usage comes from running `claude -p "/usage"` — the CLI
  authenticates *itself* against Claude Code's own credentials. Robut only
  reads the numbers it prints.

Robut never touches any keychain item — not `Claude Code-credentials`, not
one of its own. There is nothing for macOS to prompt about. Ever.

## What it shows

For each usage window — Claude's 5-hour session and weekly limits, Codex's
primary and secondary — Robut tracks how fast you're actually burning and
projects it forward:

| | |
|---|---|
| **Used** | where you are in the window |
| **Resets** | when the window rolls over |
| **Pace** | your burn rate vs. the rate you can afford |
| **Verdict** | *"comfortable"*, *"tight"*, or *"you'll run dry ~9h early"* |

The menubar robot's face reflects the worst case across every window, so a
glance is genuinely enough. Green and calm means you're fine. You only look
closer when it stops looking calm.

## Non-goals

Robut does one thing. It is not a cost dashboard, a model router, or an
everything-client for every AI provider. That restraint is the point.

## Install

Signed, notarized, and published to [Releases](../../releases), with Sparkle
for updates.

## Build from source

Requires Xcode 26+, plus `xcodegen` and `swiftlint` from Homebrew.

```sh
make install       # verify toolchain
make hooks         # install pre-commit gates
make privacy-init  # generate your local privacy denylist
make dev           # build + launch into the menubar
```

The `.xcodeproj` is generated from `project.yml` and never committed — run
`make regenerate` after changing it.

## Make targets

`make help` shows the full list. Quick reference:

- `make dev` — build and relaunch into the menubar.
- `make test` — run the Swift Testing suites.
- `make validate` — privacy + lint + typecheck + architecture + version gates.
- `make privacy` — scan the worktree for personal data.
- `make regenerate` — rebuild `Robut.xcodeproj` from `project.yml`.

## Architecture

`Core/Providers` turns each source into `UsageSnapshot` values. `Core/History`
persists samples over time. `Core/Pace` — the heart of the app — turns those
samples into a burn rate and a projection against the reset deadline. `UI`
renders the worst-case verdict as a robot face plus a detail pane.

`Core/Pace` is pure and has no dependencies on the rest of the app, which is
why it can be exhaustively tested. See `AGENTS.md` for the full map.

## Contributing

This repo is public and **must stay free of personal data**. A pre-commit
gate scans for home paths, emails, tokens, and signing identities; run
`make privacy` before pushing. Test fixtures are synthetic only — never
commit real session files. Signing config lives in `Local.xcconfig`, which
is gitignored.

## License

MIT.
