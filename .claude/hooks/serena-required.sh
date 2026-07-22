#!/usr/bin/env bash
# UserPromptSubmit hook — RETIRED / DISARMED (no-op).
#
# This hook formerly injected a "REQUIRED FIRST ACTION: initialize
# Serena" warning on every prompt until Serena was brought up — the
# enforcement of the old "Serena First — Inviolable" mandate.
#
# Serena is now SITUATIONAL, not mandatory (see .claude/rules/serena.md
# and ~/.claude/CLAUDE.md "Serena — Situational, Not Blanket"). Built-ins
# are the default; Serena is initialized ON DEMAND only, when a task
# genuinely needs symbolic ops on real-LSP code or project memory.
# Forcing init on every session is exactly the net-negative overhead a
# 2026-07 audit of 25,847 real Serena calls measured, so this nag is
# disarmed.
#
# Kept as a no-op (rather than deleted) so a skeleton sync propagates the
# disarm to existing repos without a RETIRED-list migration. Full
# retirement lands with the `agentic` tool.
exit 0
