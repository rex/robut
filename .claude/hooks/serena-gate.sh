#!/usr/bin/env bash
# PreToolUse hook — RETIRED / DISARMED (no-op).
#
# This hook formerly HARD-BLOCKED (exit 2) built-in Read/Edit/Write on
# code-file extensions once Serena was initialized, to force Serena's
# symbolic tools. It was the enforcement teeth of the old "Serena
# First — Inviolable" mandate.
#
# Serena is now SITUATIONAL (see .claude/rules/serena.md and
# ~/.claude/CLAUDE.md). Built-ins are the default substrate; Serena is a
# scalpel reached for only on symbolic ops on real-LSP languages. A
# blanket hard-block contradicts that policy — a 2026-07 audit of 25,847
# real calls found ~88% were built-ins routed through Serena for zero
# semantic gain — so the block is disarmed.
#
# Kept as a no-op (rather than deleted) so a skeleton sync propagates the
# disarm to existing repos without a RETIRED-list migration. Full
# retirement lands with the `agentic` tool.
exit 0
