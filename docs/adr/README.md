# Architectural Decision Records

This directory holds Architectural Decision Records (ADRs) in MADR 3.x
format. Use `template.md` as the starting point for new decisions.

## Index

| # | Status | Title | Date |
|---|---|---|---|
| 0001 | accepted | <Title> | YYYY-MM-DD |

## When to write an ADR

- Layering / architectural boundary changes
- Database or persistence choices
- Auth / security model changes
- Deploy / release model changes
- Library adoption with long-term lock-in
- Any decision that will be painful to reverse in >1 month

## When NOT to write an ADR

- Local implementation details
- Style or formatting decisions
- Anything a linter can enforce
- Transient task-specific choices (those go in `TASK_STATE.md`)

## Process

1. Copy `template.md` to `NNNN-short-title.md` (next available number).
2. Fill in Context, Decision Drivers, Options, Decision Outcome.
3. Open a PR with `status: proposed`.
4. Merge with `status: accepted` after review.
5. Add entry to the Index table above.

## Statuses

- `proposed` — PR open, under discussion
- `accepted` — merged; implementation may proceed
- `deprecated` — no longer the current decision; link to successor
- `superseded by NNNN` — replaced by a specific later ADR
