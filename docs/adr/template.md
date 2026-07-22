---
status: proposed
date: YYYY-MM-DD
deciders: "@<user>, #<channel>"
consulted: "@<user>"
informed: "@<team>"
tags: [<tag>, <tag>]
---

# ADR-NNNN: <Short imperative title>

## Context and Problem Statement

<3–8 sentences. State the problem and forcing function. Link to ticket or
incident if relevant.>

## Decision Drivers

- <e.g. "p99 write latency must stay <50ms">
- <e.g. "team already operates Postgres in prod">
- <e.g. "must support offline-first client">

## Considered Options

1. **Option A** — <one-line summary>
2. **Option B** — <one-line summary>
3. **Option C** — <one-line summary>

## Decision Outcome

Chosen: **Option A**, because <two sentences citing the drivers above>.

### Consequences

- **Positive**: <what gets better>
- **Negative / accepted trade-offs**: <what we accept>
- **Neutral**: <downstream work, follow-ups>

## Validation

- <metric / alert / SLO / deadline — how we'll know this decision is working>
- Revisit by: <date, 3–6 months out>

## Pros/Cons of Options

### Option A — <name>

- ✅ <pro>
- ✅ <pro>
- ❌ <con>

### Option B — <name>

- ✅ <pro>
- ❌ <con>
- ❌ <con>

### Option C — <name>

- ✅ <pro>
- ❌ <con>

## More Information

- Supersedes: ADR-NNNN (if applicable)
- Related: ADR-NNNN, ADR-NNNN
- Spike: `docs/spikes/<name>.md` (if applicable)
