# ╔══════════════════════════════════════════════════════════════════════╗
# ║  agentic-skeleton — shared Makefile core                              ║
# ║  SKELETON-OWNED. Never edit it in a consumer repo: `make              ║
# ║  sync-skeleton` replaces it and `make check-skeleton` fails on any    ║
# ║  local change.                                                        ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# The repo-owned Makefile includes this file, in this order:
#
#   1. project variables          APP_NAME, PORT, tool paths (repo-owned)
#   2. include make/agentic-skeleton.mk                     (this file)
#   3. help, stack recipes, extra targets                   (repo-owned)
#
# This file owns validate, the completion gate, every check-* gate, the
# version gate and bump-*, skeleton propagation and skill provenance. The
# repo owns everything else and MUST define `lint`, `typecheck` and
# `test`: validate and the completion gate depend on them, so a missing
# one stops make with "No rule to make target".
#
# Extending a skeleton target: add a prerequisite-only rule in the repo
# Makefile, e.g. `validate: check-openapi`. Never give a skeleton target
# a second recipe; make would replace the gate with it, and
# `make check-skeleton` rejects it.
#
# Precedence: a SHELL or color the repo sets before the include wins
# over the defaults below; command-line variables win over both. This
# file never changes the default goal: the repo's first target, or its
# own .DEFAULT_GOAL, stays the default.

ifndef AGENTIC_SKELETON_MK
AGENTIC_SKELETON_MK := 1
_AGENTIC_SKELETON_PRIOR_GOAL := $(.DEFAULT_GOAL)

# ─── Shell + colors (defaults; a repo value set earlier wins) ───────────
# Homebrew zsh, then any zsh on PATH, then /bin/bash: CI runners often
# lack zsh, and without the last fallback every recipe fails. Recipes
# here stay POSIX so bash and zsh both run them. Make's own default is
# /bin/sh, so any other value means the repo chose a shell on purpose.
ifeq ($(SHELL),/bin/sh)
SHELL := $(or $(wildcard /opt/homebrew/bin/zsh),$(shell command -v zsh),/bin/bash)
endif

ifneq ($(origin CYAN),file)
CYAN := $(shell printf '\033[36m')
endif
ifneq ($(origin GREEN),file)
GREEN := $(shell printf '\033[32m')
endif
ifneq ($(origin YELLOW),file)
YELLOW := $(shell printf '\033[33m')
endif
ifneq ($(origin RED),file)
RED := $(shell printf '\033[31m')
endif
ifneq ($(origin RESET),file)
RESET := $(shell printf '\033[0m')
endif
ifneq ($(origin BOLD),file)
BOLD := $(shell printf '\033[1m')
endif

.PHONY: validate check-if-the-agent-can-consider-this-task-completed \
        bump-patch bump-minor bump-major check-version-bumped \
        check-architecture check-docs check-precommit \
        check-skeleton sync-skeleton check-skills stamp-skill

# ─── Aggregate gates ──────────────────────────────────────────────────

## validate: Run the repo's aggregate validation flow
validate: lint typecheck check-architecture check-version-bumped check-skills
	@echo "$(GREEN)Validation complete.$(RESET)"

## check-if-the-agent-can-consider-this-task-completed: Final verification gate
check-if-the-agent-can-consider-this-task-completed: validate check-docs check-precommit test
	@echo ""
	@echo "$(BOLD)$(GREEN)✓ All gates passed. Task may be declared complete.$(RESET)"
	@echo ""
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "$(YELLOW)NOTE: working tree is dirty:$(RESET)"; \
		git status --short; \
		echo ""; \
		echo "$(YELLOW)The gates passed, but VIBE.yaml clean_worktree_required_on_completion$(RESET)"; \
		echo "$(YELLOW)may still apply. Commit or stash before declaring done.$(RESET)"; \
	fi

# ─── Versioning (non-negotiable: every commit gets a bump) ───────────

# NOTE="..." fills the new CHANGELOG entry; AGENT_NAME=... names its author.

## bump-patch: Increment patch (x.y.Z+1) — bug fixes, docs, non-behavior changes
bump-patch:
	@scripts/bump_version.py patch $(if $(NOTE),--changelog-note "$(NOTE)")

## bump-minor: Increment minor (x.Y+1.0) — additive features, backward-compatible
bump-minor:
	@scripts/bump_version.py minor $(if $(NOTE),--changelog-note "$(NOTE)")

## bump-major: Increment major (X+1.0.0) — breaking change, removal, incompat behavior
bump-major:
	@scripts/bump_version.py major $(if $(NOTE),--changelog-note "$(NOTE)")

## check-version-bumped: Fail if VERSION == HEAD's VERSION or CHANGELOG lacks matching entry
check-version-bumped:
	@if [ ! -f scripts/check_version_bumped.py ]; then \
		echo "$(RED)scripts/check_version_bumped.py is MISSING — the version$(RESET)"; \
		echo "$(RED)gate cannot run. Hard failure, never a skip. Restore it:$(RESET)"; \
		echo "$(RED)make sync-skeleton.$(RESET)"; \
		exit 1; \
	fi
	@python3 scripts/check_version_bumped.py

# ─── Required-files + architecture gates ─────────────────────────────

## check-architecture: Enforce VIBE.yaml line limits + module shape (fails closed)
check-architecture:
	@echo "$(CYAN)Checking architecture (line limits + module shape)...$(RESET)"
	@for s in check_architecture.py check_module_rules.py; do \
		if [ ! -f "scripts/$$s" ]; then \
			echo "$(RED)  scripts/$$s is MISSING — the architecture gate$(RESET)"; \
			echo "$(RED)  cannot run. Hard failure, never a skip. Restore it:$(RESET)"; \
			echo "$(RED)  make sync-skeleton.$(RESET)"; \
			exit 1; \
		fi; \
	done
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_architecture.py && uv run scripts/check_module_rules.py; \
	elif python3 -c 'import yaml' >/dev/null 2>&1; then \
		python3 scripts/check_architecture.py && python3 scripts/check_module_rules.py; \
	else \
		echo "$(RED)  Architecture gate cannot run: no 'uv', and no$(RESET)"; \
		echo "$(RED)  python3 with PyYAML. Install uv: https://docs.astral.sh/uv/$(RESET)"; \
		exit 1; \
	fi

## check-docs: Enforce VIBE.yaml docs.*_required (fails closed)
check-docs:
	@echo "$(CYAN)Checking required collaboration files (VIBE.yaml docs)...$(RESET)"
	@if [ ! -f scripts/check_docs.py ]; then \
		echo "$(RED)  scripts/check_docs.py is MISSING — the docs gate$(RESET)"; \
		echo "$(RED)  cannot run. Hard failure. make sync-skeleton.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_docs.py; \
	elif python3 -c 'import yaml' >/dev/null 2>&1; then \
		python3 scripts/check_docs.py; \
	else \
		echo "$(RED)  docs gate cannot run: no 'uv', no python3 + PyYAML.$(RESET)"; \
		exit 1; \
	fi

## check-precommit: Verify the pre-commit hook is installed (fails closed)
check-precommit:
	@echo "$(CYAN)Checking the pre-commit enforcement surface...$(RESET)"
	@if [ ! -f .pre-commit-config.yaml ]; then \
		echo "$(RED)  .pre-commit-config.yaml is MISSING — the commit-time$(RESET)"; \
		echo "$(RED)  enforcement surface is absent. Re-run the bootstrap.$(RESET)"; \
		exit 1; \
	fi
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "$(RED)  pre-commit is not installed — it is MANDATORY, not$(RESET)"; \
		echo "$(RED)  optional. Install it: uv tool install pre-commit$(RESET)"; \
		exit 1; \
	fi
	@HOOK=$$(git rev-parse --git-path hooks/pre-commit 2>/dev/null); \
	if [ -z "$$HOOK" ] || [ ! -f "$$HOOK" ] || ! grep -q pre-commit "$$HOOK" 2>/dev/null; then \
		echo "$(RED)  the pre-commit git hook is NOT installed. Run:$(RESET)"; \
		echo "$(RED)    pre-commit install$(RESET)"; \
		echo "$(RED)  A .pre-commit-config.yaml with no installed hook$(RESET)"; \
		echo "$(RED)  enforces nothing — fail closed.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)  pre-commit hook installed.$(RESET)"

# ─── Skeleton propagation + skill provenance ─────────────────────────

## check-skeleton: Report drift vs the installed agentic-skeleton (fails closed)
check-skeleton:
	@echo "$(CYAN)Checking skeleton-owned files for drift...$(RESET)"
	@if [ ! -f scripts/sync_skeleton.py ]; then \
		echo "$(RED)  scripts/sync_skeleton.py is MISSING — cannot check$(RESET)"; \
		echo "$(RED)  skeleton drift. Re-run the agentic-skeleton bootstrap.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_skeleton.py --check; \
	else \
		python3 scripts/sync_skeleton.py --check; \
	fi

## sync-skeleton: Pull current skeleton-owned files into this repo
sync-skeleton:
	@if [ ! -f scripts/sync_skeleton.py ]; then \
		echo "$(RED)  scripts/sync_skeleton.py is MISSING.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_skeleton.py --apply; \
	else \
		python3 scripts/sync_skeleton.py --apply; \
	fi

## check-skills: Advisory applied-skill provenance + drift report (never fails validate)
check-skills:
	@echo "$(CYAN)Checking applied-skill provenance...$(RESET)"
	@if [ ! -f scripts/check_skills.py ]; then \
		echo "$(YELLOW)  scripts/check_skills.py not present — run 'make sync-skeleton'.$(RESET)"; \
	elif command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_skills.py || true; \
	else \
		python3 scripts/check_skills.py || true; \
	fi

## stamp-skill: Record that a skill was applied (SKILL=<id> [VERSION=x.y.z])
stamp-skill:
	@if [ -z "$(SKILL)" ]; then \
		echo "$(RED)Usage: make stamp-skill SKILL=<id> [VERSION=x.y.z]$(RESET)"; exit 1; \
	fi
	@if [ ! -f scripts/stamp_skill.py ]; then \
		echo "$(RED)  scripts/stamp_skill.py missing — run 'make sync-skeleton'.$(RESET)"; exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/stamp_skill.py "$(SKILL)" $(if $(VERSION),--version "$(VERSION)"); \
	else \
		python3 scripts/stamp_skill.py "$(SKILL)" $(if $(VERSION),--version "$(VERSION)"); \
	fi

# Restore the default goal as the repo left it before the include, so
# the repo's first target (usually `help`) stays the default.
.DEFAULT_GOAL := $(_AGENTIC_SKELETON_PRIOR_GOAL)
endif
