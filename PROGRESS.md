# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: <name> (<stack>)
- **Active branch**: <branch>
- **Active feature spec**: `specs/<slug>/`
- **Active TASK_STATE**: `TASK_STATE.md` (<phase> / <slice>)
- **Last session**: <date> (<agent>, ~<tokens> tokens, <`/clear` or `/compact` at end>)

## Last three decisions

- <date> <decision> (<ADR link if any>)
- <date> <decision>
- <date> <decision>

## Open blockers

- <blocker> (<who owns it>)

## How to resume (for a fresh agent)

1. Read `AGENTS.md` then `TASK_STATE.md` §0 and current slice.
2. Skim `specs/<slug>/plan.md` for the active phase.
3. Do NOT re-plan if the plan is frozen — follow it.
4. Run `make test` to see current failing test.

## Do NOT

- Edit <file> (frozen this phase)
- Touch <directory> (separate change)
- Write new specs — we are in implementation, not planning
