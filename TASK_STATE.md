# TASK_STATE — <feature-name>

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions.
>
> Spec: `specs/<slug>/spec.md` · Plan: `specs/<slug>/plan.md`
> Branch: `main` · Owner: repo maintainer · Last update: 2026-07-22 by Claude Opus 4.8

## 0. TL;DR for a fresh agent session

Building **Robut** — a macOS menubar app showing Claude + Codex usage with
burn-rate projection ("will my current pace last until reset?"). Phase 0
(scaffold + privacy gate) is **done**. **Next action: Slice 1.1** — the
`project.yml` + app skeleton that builds and launches into the menubar.

**Read `AGENTS.md` §1 and §9 before touching anything.** Two hard rules:
this is a **public repo** (no personal data, ever — `make privacy`), and
Robut must **never read another app's keychain item** (that is the exact
bug it exists to fix).

## Standing user directives

<!-- Record durable per-task user directives here. "Continue until blocked",
     "do not wait for my input unless blocked", "skip tests for this slice"
     — anything the maintainer said that should survive compaction.
     PUBLIC REPO: paraphrase directives; never record personal details. -->

- **Autonomy: continue-until-blocked.** Build straight through; stop only on
  a hard blocker or a decision that is the maintainer's to make.
- **Tests are a required gate**, focused on the pace/projection engine.
- **CI is deferred** until the app builds; use `macos-latest` runners when added.
- **Never read another app's keychain item.** Robut owns its own credential.

## 1. Phases

| # | Phase | Status | Exit criteria |
|---|---|---|---|
| 1 | <phase name> | ⏸ pending | <what's true when this phase is done> |
| 2 | <phase name> | ⏸ pending | <...> |

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices (vertical, atomic, independently mergeable)

### Slice 1.1 — <imperative title>

- Status: ⏸ pending
- Owner: <agent or human>
- Files (planned edits): `<path>`, `<path>`
- Files (do NOT edit): `<path>`
- Depends on: (none) | Slice X.Y
- Acceptance (EARS notation):
  - [ ] When <trigger>, the system shall <behavior>.
  - [ ] While <state>, the system shall <constraint>.
  - [ ] If <event>, then the system shall <response>.
  - [ ] Tests: <test names>
  - [ ] Lint + typecheck green

### Slice 1.2 — <next>

- Status: ⏸ pending
- Files (planned edits): ...

## 3. Blockers / open questions

- (none yet)

## 4. Recent decisions (append-only, newest first)

- <date> — <decision> (<who decided>, <context>)

## 5. Next actions (ordered)

1. <immediate next action>
2. <then>
3. <then>

## 6. Handoff note (fill when ending a session)

<Last session>: <what was accomplished, what's half-finished, where to
resume. Specific files + failing tests if applicable.>
