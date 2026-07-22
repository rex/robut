# MAP

<!-- Repo map for humans and agents. Keep under 80 lines.
     Update when you add a domain, a module, or a hot path. -->

## Domains

| Domain | Purpose | Entry point | Owner |
|---|---|---|---|
| <domain-a> | <what it does> | `<src>/<domain-a>/router.py` | @<owner> |

## Extension points

- <extension point 1> — <where to add new X>
- <extension point 2> — <how to register a new Y>

## Where bodies are buried

<!-- The 3–5 weirdest things about this repo. Save the next agent 2 hours. -->

- (none yet)

## Do not edit without ADR

- <module or file> — <reason>

## Hot paths (watch performance)

- <path> — <latency target>

## Cold paths (rarely touched)

- <path> — <reason>

## Cross-cutting concerns

- Auth: <where it lives>
- Logging: `<src>/logging.py`
- Config: `<src>/config/settings.py`
- Error handling: `<src>/main.py` (single exception handler)

## External dependencies

| System | What we call | When | Failure mode |
|---|---|---|---|
| <system-a> | <API/lib> | <what triggers it> | <behavior on outage> |

## Quick tour (read order for a new contributor)

1. `README.md` — human-readable entry point.
2. `AGENTS.md` — agent-readable project contract.
3. `CONVENTIONS.md` — how to write code here.
4. This file — where things live.
5. `specs/<active>/` — what's being built right now.
6. `docs/adr/README.md` — why we made the decisions we made.

## Agents: when to read what

- Grep for symbols? Use Serena MCP, not raw grep.
- Add a feature? Read `specs/<active>/spec.md` + `plan.md`, then the slice's
  listed files.
- Fix a bug? Read `TASK_STATE.md` for context, then the affected module's
  `README.md`, then the code.
- Refactor? Check `docs/adr/` for constraints before starting.
