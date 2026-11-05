---
name: "source-command-sync-skills"
description: "Refresh skill-sourced .Codex/ files from the installed agentic-skeleton templates."
---

# source-command-sync-skills

Use this skill when the user asks to run the migrated source command `sync-skills`.

## Command Template

# /sync-skills — pull updated infrastructure files from skills

Run this when the upstream agentic-skeleton skill has been updated and
you need to bring this repo's `.Codex/` infrastructure files in sync.
Covers hooks, rules, commands, and agents — not repo-specific content.

## Source directories

Brownfield source (prefer this for retrofitted repos):
```
~/.Codex/skills/agentic-skeleton/templates/brownfield/PR5-delegation-hooks/files/
```

Greenfield source (fallback for files not found above):
```
~/.Codex/skills/agentic-skeleton/templates/greenfield/
```

## What to sync

For every file under `.Codex/` in this repo, check whether a
matching file exists in the brownfield source (same relative path).
If yes: read the source and overwrite the local file.
If not in brownfield source: check the greenfield source.
If not in either source: leave the local file untouched.

Directories in scope: `.Codex/hooks/`, `.Codex/rules/`,
`.Codex/commands/`, `.Codex/agents/`.

## What NOT to touch

- `.Codex/settings.json` — wires hooks and permissions; repo-specific,
  can't be safely overwritten. Update manually if needed.
- `VIBE.yaml` — repo policy, repo-specific.
- `AGENTS.md` — repo-specific.
- `.mcp.json` — repo-specific.
- Any file under `.Codex/` that has NO matching source file.

## Procedure

1. Confirm the skill source exists:
   ```bash
   ls ~/.Codex/skills/agentic-skeleton/templates/brownfield/PR5-delegation-hooks/files/.Codex/
   ```
   If missing, stop and tell the user to run `make sync-links` in the
   agent-skills repo.

2. For each local file in `.Codex/hooks/`, `.Codex/rules/`,
   `.Codex/commands/`, `.Codex/agents/`: find the corresponding
   source file in brownfield (falling back to greenfield), read it,
   and write the local copy.

3. Show a summary of which files were updated and which were unchanged
   (diff at a glance — filenames only, not full diffs).

4. If any files changed, commit:
   ```
   chore: sync .Codex/ infrastructure from agentic-skeleton
   ```
   No PR needed — this is a maintenance update, not a feature branch.

## After syncing

Hook changes take effect on the next session — `settings.json` wiring is
read at session start, so restart the session (or `/clear`) before
relying on an updated hook.
