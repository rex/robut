# Serena rules (situational use + edit discipline)

> Loaded by Claude Code as a project-level rule when present at
> `.claude/rules/serena.md`. Serena is a **situational scalpel, not the
> default substrate** — built-ins (Read/Edit/Write/Grep/Glob/LS) are the
> default for all file I/O; use Serena only for genuinely symbolic
> operations on real-LSP languages. Full protocol:
> `~/.claude/skills/serena/references/protocol.md`. Rationale + the audit
> that set this policy: `agent-skills/docs/serena-analysis/`.

## When to use Serena — and when not

**Use Serena** when BOTH hold:

- The file is a **real-LSP language**: ts/tsx/js/jsx, python, go, rust,
  java, kotlin, c/c++, scala, ruby — AND
- The operation is **symbolic**: whole-symbol replacement, symbol-anchored
  insertion, a structural overview before editing, a reference-safe
  refactor (rename / find-references / safe-delete), or LSP diagnostics
  without a build.

**Use built-ins** for everything else:

- **No-symbol-graph files** — Markdown, YAML, JSON, TOML, .env, shell,
  HTML/CSS, Dockerfile, templates. An LSP adds nothing; use `Read` /
  `Edit` / `Grep`.
- **Plain-text ops** — whole-file read, substring/regex search, literal
  find/replace, new-file creation, directory listing.
- **Swift** — SourceKit-LSP is too flaky to prefer. Built-ins for edits;
  reach for `get_symbols_overview` / diagnostics only opportunistically
  and fall back on the first error.
- **When unsure** — built-ins are the safe default. Serena is the
  exception you justify, not the rule you obey.

**Parallel fleets:** Serena is **parallel-unsafe** (one shared server,
one active project; cross-repo contamination is verified). Any
multi-subagent / workflow wave runs **built-ins-only, never Serena**.

**On any Serena error:** fall **straight** to the built-in equivalent.
Do not retry-loop the schema.

## Initializing Serena (only when you'll actually use it)

Serena's tools are deferred in Claude Code (schemas not preloaded). When
a task genuinely needs symbolic ops or project memory — and only then —
bring it up on demand:

1. `ToolSearch` to load the schemas, then
2. `mcp__serena__initial_instructions`, then `activate_project` (project
   name or `.`), then `check_onboarding_performed`. Onboard or
   `list_memories` as the task needs.

This is optional and on-demand — **not** a mandatory first action.

## Edit discipline (when you DO use Serena)

Exploration pyramid: `mcp__serena__get_symbols_overview` →
`mcp__serena__find_symbol(depth=1, include_body=False)` →
`mcp__serena__find_symbol(include_body=True)`. Going straight to bodies
burns tokens.

- Call `find_symbol` with **`name_path_pattern`** (NOT `name_path` — the
  wrong param name fails schema validation and causes ~20% of
  find_symbol errors).
- Symbolic edits over line edits when a symbol is the unit of change:
  `replace_symbol_body`, `insert_before_symbol` / `insert_after_symbol`,
  `rename_symbol` (LSP-correct project-wide), `safe_delete_symbol`.
- Diagnostics without a build: `get_diagnostics_for_file` /
  `get_diagnostics_for_symbol`.
- Pattern search (only when already in a Serena flow):
  `search_for_pattern` — gitignore-aware, DOTALL+MULTILINE Python regex.
  Use `.*?` (non-greedy) between anchors, never `.*`. Otherwise `Grep`.

## Memory discipline — keep this proactively (the durable win)

The memory tools have no built-in equivalent and are the part of Serena
that most reliably earns its keep. Use them regardless of language.

- **Project memories** live in `<project>/.serena/memories/` —
  architecture decisions, in-progress task state, gotchas.
- **Global memories** (`global/<topic>` prefix) live in
  `~/.serena/memories/global/`, shared across all projects — code-style
  conventions, team-wide rules, agent-behavior guidance.
- Memory names use **underscores**, not spaces. `/` makes subdirectories.
  No `..` (Serena rejects).
- **Memory-as-handoff**: at the end of a long-running task, summarize
  state to `tasks/<feature>/state` so the next session can resume —
  Serena's documented context-window-exhaustion continuation pattern.
- Read each memory at most once per session — cache content yourself.

## Critical gotchas (when using Serena)

These bite repeatedly. Burn them in.

- **Line numbers are 0-based** in every Serena tool. Humans say "line
  42"; you must use 41.
- **`replace_content` backreferences are `$!1`, NOT `\1`.** Distinct
  from every other regex tool you know.
- **`activate_project` for project-switching is disabled in
  single-project contexts** (`claude-code`, `ide`, `vscode`). It IS
  required for first-time project registration — call it in the init
  chain if Serena has no active project. To switch projects mid-session,
  restart Serena with `--project <new>`.
- **`onboarding` should be called at most once per conversation.** If
  memories were lost, prefer `list_memories` + targeted `write_memory`
  over re-running the full sweep.

## Dashboard

`http://localhost:24282/dashboard/index.html` (port increments if
multiple instances). Shows tool-call history, live logs, edit
memories/config in browser. `mcp__serena__open_dashboard` triggers it.

## See also

- `~/.claude/skills/serena/references/protocol.md` — full agent-agnostic
  protocol with tool inventory, modes, contexts, multi-agent HTTP,
  language-server coverage.
- `agent-skills/docs/serena-analysis/` — the 25,847-call audit and the
  decision to demote Serena from mandate to situational tool.
