# <module-name>

<One sentence: what this module does and who uses it.>

## Status

🟢 <Production | Beta | Experimental> · Owner: @<team> · SLO: <target>

## Why this exists

<2–4 sentences. State the problem, not the solution.>

## Public API

<What callers use. Agents: do NOT depend on anything not listed here.>

- `<fn_name>(<args>) -> <return>` — <one-line behavior>
- `<fn_name>(<args>) -> <return>` — <one-line behavior>

Exported from `__init__.py` / `index.ts`. Everything else is internal.

## Architecture

```
<ascii flow: input → step → step → step → output>
```

- Depends on: `<module>`, `<module>`
- Depended on by: `<module>`, `<module>`

## Files

- `<file>` — <one-line purpose; where to start reading>
- `<file>` — <one-line purpose>

## Invariants

- <invariant 1 — what must always be true>
- <invariant 2>

## Common tasks

- **Add <X>**: extend `<file>` <how>, add fixture, add test
- **Change <Y>**: ADR required (`docs/adr/...`), then <process>

## Gotchas

- <thing that looks simple but isn't>

## Related

- ADR-<NNNN> · Runbook: `docs/runbooks/<name>.md`
