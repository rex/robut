# Robut Statistics Matrix

> The complete inventory of statistics Robut captures, for designing the
> data-exploration surface. Capture shipped in v0.18.0 (`Core/Stats/`);
> display is unbuilt on purpose — this document is the design handoff.
> All examples below are SYNTHETIC.

## How capture works (one paragraph)

An actor (`UsageStatsStore`) owns a local ledger persisted to Application
Support. Every ~10 minutes the refresh loop runs three incremental
scanners (per-file byte cursors — the multi-gigabyte first scan happens
once) over Claude Code's transcripts, Codex's rollouts, and the prompt
history file; the Claude CLI source also forwards its raw `/usage` text so
the analytics block is parsed from a call Robut already makes. Everything
is read-only, machine-local, and never leaves the device. Display layers
read one call: `await model.stats.snapshot()` → `StatsSnapshot`.

## The datasets

### 1. Daily token rollups — the core series

| | |
|---|---|
| **Source** | `~/.claude/projects/**/*.jsonl` (per-message `usage`) + `~/.codex/sessions/**/*.jsonl` (`token_count` cumulative deltas) |
| **Depth** | One bucket per **day × provider × model × project**; months of history (bounded at 400 days) |
| **Breadth** | 2 providers · every model ever used (real data shows 15+) · every project directory |
| **Format** | `DailyRollup { day: "2026-07-23", provider, model, project, tally: TokenTally, messages: Int, sidechainMessages: Int }` |
| **TokenTally** | `input, output, cacheRead, cacheWrite5m, cacheWrite1h, reasoning` (all `Int`; `total` computed; `reasoning` is Codex-only, a subset of output) |
| **Refresh** | Incremental, ≤10 min behind |
| **Caveats** | THIS machine, these CLIs only (no claude.ai web, no other devices — the CLI's own caveat). Claude transcripts prune (~60–90 days observed); Codex keeps everything, so Codex history reaches back further. |

**Display ideas**: usage-per-day bars (stacked by provider or model);
30-day totals; per-project treemap; cache-read vs fresh-token split
(cache reads dominate by ~100:1 — a story in itself); main-vs-subagent
share (`sidechainMessages / messages`).

### 2. API-equivalent cost — derived, not stored

| | |
|---|---|
| **Source** | `PriceTable.cost(of:model:)` applied to any rollup at read time |
| **Depth** | Same as rollups (recomputable for any slice: day, model, project) |
| **Format** | `Double?` USD — nil for unpriced models (display "unpriced", never drop) |
| **Basis** | List prices snapshotted 2026-07 (table in `PriceTable.swift`): Anthropic Opus $5/$25, Sonnet $3/$15, Haiku $1/$5, Fable $10/$50 per MTok; OpenAI gpt-5.6 sol $5/$30, terra $2.50/$15, luna $1/$6. Cache reads 10% of input; writes 1.25× (5m) / 2× (1h). |
| **Caveats** | An ESTIMATE by construction — this is "what the same tokens would have cost on the API", the subscription-justifier number. Prices drift; the table is versioned and updatable. |

**Display ideas**: the hero number ("your subscription did $X of API work
this month"); $/day series; cost by model donut; "cache savings" (what
cache reads would have cost at full input price minus what they cost).

### 3. Usage insights — the CLI's own analytics (was thrown away)

| | |
|---|---|
| **Source** | The `claude /usage` text Robut already fetches every ~2 min (no extra calls) |
| **Depth** | Latest snapshot of two rolling windows (24h, 7d) + one 24h-window snapshot archived per day (a time series of the rolling count) |
| **Format** | `InsightsWindow { period: "24h"/"7d", requests: Int, sessions: Int, traits: [InsightShare], topSkills/topSubagents/topMCPServers: [InsightShare] }` where `InsightShare { name, sharePercent }` |
| **Traits** | Behavioral shares, e.g. "of your usage was at >150k context" → 84, "came from subagent-heavy sessions" → 44 |
| **Caveats** | Anthropic's own numbers (approximate, this machine, per their fine print). Text format is not a contract — parser is tolerant, drops what it can't read. |

**Display ideas**: "why is my week burning" panel — requests/sessions
counters, trait bars, top-subagents/top-MCP leaderboards. This pairs
directly with the pace verdict: the verdict says *whether* you'll make
it, insights say *what's eating it*.

### 4. Quota estimates — the tokens-per-percent correlation (novel)

| | |
|---|---|
| **Source** | Derived: percent-used deltas (usage history) ÷ local tokens consumed in the same interval (hourly series) |
| **Depth** | One estimate per usage window (`claude.session`, `claude.weekly`, `claude.weekly.Fable`, `codex.weekly`, …), continuously re-derived |
| **Format** | `QuotaEstimate { windowID, tokensPerPercent: Double, estimatedWindowTokens: Double, sampleCount: Int, asOf: Date }` |
| **Method** | Median ratio over intervals with ≥1 percentage-point movement and ≤48h span; refuses to estimate below 2 clean intervals |
| **Caveats** | A LOWER bound: local tokens vs an account-wide percent (other devices/surfaces consume percent invisibly). Accurate when this machine dominates. Token weighting inside providers' quota math is unknown — this uses raw volume. |

**Display ideas**: turn every percent into tokens — "8% used ≈ 650M
tokens", "≈ 7.4B tokens left this week"; window-size reveal ("your weekly
quota ≈ 8B tokens"); confidence shown via sampleCount.

### 5. Prompt activity

| | |
|---|---|
| **Source** | `~/.claude/history.jsonl` (one line per submitted prompt) |
| **Depth** | Per-day: prompt count, distinct session count, distinct projects touched. Months of history. |
| **Format** | `PromptActivity { prompts: Int, sessionIDs: Set<String>, projects: Set<String> }` keyed by day |
| **Caveats** | Claude Code prompts only (not Codex; Codex sessions are visible in rollups instead). |

**Display ideas**: activity heatmap (GitHub-contributions style);
prompts/day vs tokens/day overlay (measures leverage per prompt).

### 6. Codex plan & credits

| | |
|---|---|
| **Source** | `rate_limits` in every Codex rollout (fields previously unparsed) |
| **Format** | `CodexPlanInfo { planType: "plus", hasCredits, creditsUnlimited, creditBalance, asOf }` |
| **Display** | Plan chip next to the CODEX group header; credit state when relevant. |

### 7. Hourly token series (internal, but exposable)

| | |
|---|---|
| **Source** | Same scans, bucketed by hour instead of day |
| **Depth** | 21 days of hours per provider |
| **Format** | `[ "provider|hourEpoch" : TokenTally ]` |
| **Purpose** | Feeds the quota correlation; also renders as a fine-grained "when do I burn" clock/heat view (hour-of-day × day grid). |

## Read model

```swift
let snapshot = await model.stats.snapshot()
// snapshot.daily          [DailyRollup]
// snapshot.hourly         ["provider|hourEpoch": TokenTally]
// snapshot.insights       UsageInsights?          (latest)
// snapshot.insightsByDay  [day: InsightsWindow]   (24h window archived daily)
// snapshot.promptsByDay   [day: PromptActivity]
// snapshot.codexPlan      CodexPlanInfo?
// snapshot.quotaEstimates [windowID: QuotaEstimate]
// snapshot.lastScan       Date?
PriceTable.cost(of: someTally, model: "claude-opus-4-8")  // USD estimate
```

## Cross-cutting caveats (surface these in the UI, don't hide them)

1. **Local lens vs account truth.** Token counts cover this Mac's CLIs.
   The percentage windows (already in the pane) remain the account-wide
   truth. Never present token counts as "your account's usage".
2. **Costs are API-equivalent estimates** at snapshotted list prices.
3. **Quota estimates are lower bounds** with a stated sample count.
4. **History depth differs by provider** (Codex keeps everything; Claude
   transcripts prune) — a combined all-time chart will look asymmetric.
5. Everything is local and read-only; nothing is transmitted anywhere.
