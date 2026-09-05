# ╔══════════════════════════════════════════════════════════════════════╗
# ║          robut — Makefile                                            ║
# ║          Swift 6 / SwiftUI macOS menubar app (xcodegen)              ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# Usage: make <target>
# Run `make help` for a full list of available targets.

.PHONY: help help-stack install env env-check setup validate update info \
        regenerate run archive notarize release hooks privacy privacy-init signing-init \
        dev build start lint typecheck check-architecture check-docs \
        check-precommit check-skeleton sync-skeleton check-skills stamp-skill fix test \
        bump-patch bump-minor bump-major check-version-bumped version \
        clean clean-all \
        docker-build docker-run docker-stop docker-clean \
        db-generate db-push db-migrate db-studio db-reset \
        check-if-the-agent-can-consider-this-task-completed

# ─── Configuration ────────────────────────────────────────────────────
# Prefer Homebrew zsh on macOS, then any zsh on PATH, then /bin/bash as
# a CI-runner fallback (most CI runners don't ship zsh by default;
# without this third fallback SHELL resolves to '' and `make: -c: No
# such file or directory` fires on the first recipe). Keep recipes
# POSIX-compatible — no `[[ ]]`, no `${var//foo/bar}` substitution, no
# zsh globbing — so /bin/bash works as a true fallback.
SHELL       := $(or $(wildcard /opt/homebrew/bin/zsh),$(shell command -v zsh),/bin/bash)
# xcpretty is Ruby and dies on non-ASCII build output under a C/POSIX locale.
export LC_ALL ?= en_US.UTF-8
APP_NAME    ?= Robut
DOCKER_IMAGE := $(APP_NAME):latest

# ─── Apple toolchain (lang-swift-apple overlay) ───────────────────────
XCODEGEN    ?= xcodegen
XCODEBUILD  ?= xcodebuild
PROJECT     ?= $(APP_NAME).xcodeproj
SCHEME      ?= $(APP_NAME)
DEST        ?= platform=macOS,arch=arm64
CONFIG      ?= Debug
DERIVED     ?= DerivedData
# Tests/typecheck build with CODE_SIGNING_ALLOWED=NO, which re-signs the
# product ad-hoc. If that landed in $(DERIVED), it would clobber the
# stably-signed app that `make start` launches — and an ad-hoc build
# reintroduces the keychain-prompt bug. So they build into a SEPARATE
# path and never touch the runnable product.
DERIVED_TEST ?= $(DERIVED)-test
BUILT_APP   := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
# Monotonic build number; agrees between local Xcode builds and CI.
BUILD_NUM   := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
MARKETING   := $(shell cat VERSION 2>/dev/null || echo 0.1.0)
# xcpretty if available, else passthrough (never let it swallow failures).
FMT         := $(shell command -v xcpretty >/dev/null 2>&1 && echo "| xcpretty" || echo "")

# Colors for output
CYAN   := $(shell printf '\033[36m')
GREEN  := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RED    := $(shell printf '\033[31m')
RESET  := $(shell printf '\033[0m')
BOLD   := $(shell printf '\033[1m')

# ─── Help ─────────────────────────────────────────────────────────────

## help: Display this help message with all available targets
help:
	@echo ""
	@echo "$(BOLD)$(CYAN)$(APP_NAME)$(RESET)"
	@echo "$(CYAN)════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(BOLD)Setup & Installation$(RESET)"
	@echo "  $(GREEN)make install$(RESET)              Install dependencies"
	@echo "  $(GREEN)make env$(RESET)                  Create .env from template"
	@echo "  $(GREEN)make env-check$(RESET)            Verify required env vars"
	@echo "  $(GREEN)make setup$(RESET)                Full setup: install + env + typecheck"
	@echo ""
	@echo "$(BOLD)Development$(RESET)"
	@echo "  $(GREEN)make dev$(RESET)                  Start dev server (port $(PORT))"
	@echo "  $(GREEN)make build$(RESET)                Build production bundle"
	@echo "  $(GREEN)make start$(RESET)                Start production server"
	@echo "  $(GREEN)make lint$(RESET)                 Run linter"
	@echo "  $(GREEN)make typecheck$(RESET)            Run type checker"
	@echo "  $(GREEN)make check-architecture$(RESET)   Run repo-native architecture checks"
	@echo "  $(GREEN)make fix$(RESET)                  Auto-fix lint issues"
	@echo "  $(GREEN)make test$(RESET)                 Run tests (when testing is enabled)"
	@echo "  $(GREEN)make validate$(RESET)             Run aggregate validation: lint + typecheck + architecture + version-gate"
	@echo "  $(GREEN)make check-skills$(RESET)         Advisory: applied-skill provenance + drift (never fails)"
	@echo "  $(GREEN)make stamp-skill$(RESET)          Record an applied skill: SKILL=<id> [VERSION=x.y.z]"
	@echo ""
	@echo "$(BOLD)Versioning (required before every commit)$(RESET)"
	@echo "  $(GREEN)make version$(RESET)              Print current VERSION"
	@echo "  $(GREEN)make bump-patch$(RESET)           Bump patch (x.y.Z+1) — bug fixes / doc / refactor"
	@echo "  $(GREEN)make bump-minor$(RESET)           Bump minor (x.Y+1.0) — additive feature, backward-compat"
	@echo "  $(GREEN)make bump-major$(RESET)           Bump major (X+1.0.0) — breaking change"
	@echo ""
	@echo "$(BOLD)Docker$(RESET)"
	@echo "  $(GREEN)make docker-build$(RESET)         Build Docker image"
	@echo "  $(GREEN)make docker-run$(RESET)           Run container (port $(PORT))"
	@echo "  $(GREEN)make docker-stop$(RESET)          Stop container"
	@echo "  $(GREEN)make docker-clean$(RESET)         Remove image and container"
	@echo ""
	@echo "$(BOLD)Maintenance$(RESET)"
	@echo "  $(GREEN)make clean$(RESET)                Remove build cache"
	@echo "  $(GREEN)make clean-all$(RESET)            Remove build cache + deps (destructive!)"
	@echo "  $(GREEN)make update$(RESET)               Update dependencies"
	@echo "  $(GREEN)make info$(RESET)                 Show project info"
	@echo ""
	@echo "$(BOLD)Release (Developer ID + notarization + Sparkle)$(RESET)"
	@echo "  $(GREEN)make notary-init$(RESET)          One-time: store notarization credentials in your keychain"
	@echo "  $(GREEN)make notarize$(RESET)             Archive → export → notarize → staple (build/release/)"
	@echo "  $(GREEN)make release$(RESET)              Package → signed appcast → tag → GitHub Release"
	@echo "  $(GREEN)make sparkle-keys-init$(RESET)    One-time: Sparkle EdDSA keypair (public key → Info.plist)"
	@echo "  $(GREEN)make release-clean$(RESET)        Remove build/release and dist"
	@echo ""
	@echo "$(BOLD)Completion$(RESET)"
	@echo "  $(GREEN)make check-if-the-agent-can-consider-this-task-completed$(RESET)"
	@echo "    Final verification gate (required before declaring a task complete)"
	@echo ""
	@echo "$(BOLD)Variables$(RESET)"
	@echo "  PORT=$(PORT)  (override: make dev PORT=3000)"
	@echo ""

# ─── Setup & Installation ────────────────────────────────────────────

## install: Verify the Apple toolchain is present (SPM deps resolve at build time)
install:
	@echo "$(CYAN)Checking Apple toolchain...$(RESET)"
	@command -v $(XCODEGEN) >/dev/null 2>&1 || { \
		echo "$(RED)  xcodegen missing — brew install xcodegen$(RESET)"; exit 1; }
	@command -v $(XCODEBUILD) >/dev/null 2>&1 || { \
		echo "$(RED)  xcodebuild missing — install Xcode + xcode-select --install$(RESET)"; exit 1; }
	@command -v swiftlint >/dev/null 2>&1 || \
		echo "$(YELLOW)  swiftlint missing (lint gate will fail) — brew install swiftlint$(RESET)"
	@echo "$(GREEN)Toolchain OK.$(RESET)"

## env: Create .env from template if missing
env:
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			echo "$(YELLOW)Creating .env from .env.example...$(RESET)"; \
			cp .env.example .env; \
			echo "$(GREEN).env created. Configure before running.$(RESET)"; \
		else \
			echo "$(RED)No .env.example to copy from.$(RESET)"; exit 1; \
		fi \
	else \
		echo "$(YELLOW).env already exists, skipping.$(RESET)"; \
	fi

## env-check: Verify required env vars are set
env-check:
	@if [ ! -f .env ]; then echo "$(RED).env missing — run 'make env'.$(RESET)"; exit 1; fi
	@echo "$(GREEN).env present.$(RESET)"

## setup: Full project setup
setup: install env typecheck
	@echo ""
	@echo "$(GREEN)$(BOLD)Setup complete!$(RESET)"
	@echo "  Run $(CYAN)make dev$(RESET) to start developing."

## validate: Run the repo's aggregate validation flow
validate: privacy lint typecheck check-architecture check-version-bumped check-skills
	@echo "$(GREEN)Validation complete.$(RESET)"

# ─── Versioning (non-negotiable: every commit gets a bump) ───────────

## bump-patch: Increment patch (x.y.Z+1) — bug fixes, docs, non-behavior changes
bump-patch:
	@scripts/bump_version.py patch

## bump-minor: Increment minor (x.Y+1.0) — additive features, backward-compatible
bump-minor:
	@scripts/bump_version.py minor

## bump-major: Increment major (X+1.0.0) — breaking change, removal, incompat behavior
bump-major:
	@scripts/bump_version.py major

## check-version-bumped: Fail if VERSION == HEAD's VERSION or CHANGELOG lacks matching entry
check-version-bumped:
	@if [ ! -f scripts/check_version_bumped.py ]; then \
		echo "$(RED)scripts/check_version_bumped.py is MISSING — the version$(RESET)"; \
		echo "$(RED)gate cannot run. Hard failure, never a skip — restore it via$(RESET)"; \
		echo "$(RED)re-run the agentic-skeleton bootstrap to restore it.$(RESET)"; \
		exit 1; \
	fi
	@python3 scripts/check_version_bumped.py

## version: Print current VERSION
version:
	@cat VERSION 2>/dev/null || echo "0.1.0 (VERSION file missing)"

# ─── Development ──────────────────────────────────────────────────────

## regenerate: Regenerate Robut.xcodeproj from project.yml (never committed)
regenerate:
	@echo "$(CYAN)xcodegen generate...$(RESET)"
	@$(XCODEGEN) generate --quiet
	@echo "$(GREEN)$(PROJECT) regenerated.$(RESET)"

## dev: Build and relaunch Robut in the menubar (the inner loop)
dev: build start

## build: Build the macOS app bundle
build: regenerate
	@echo "$(CYAN)Building $(APP_NAME) ($(CONFIG))...$(RESET)"
	@set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-configuration $(CONFIG) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED) \
		MARKETING_VERSION=$(MARKETING) CURRENT_PROJECT_VERSION=$(BUILD_NUM) \
		build $(FMT)
	@echo "$(GREEN)Built → $(BUILT_APP)$(RESET)"

## start: Relaunch the built app (kills any running instance first)
start:
	@if [ ! -d "$(BUILT_APP)" ]; then \
		echo "$(RED)Not built yet — run 'make build'.$(RESET)"; exit 1; fi
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@open "$(BUILT_APP)"
	@echo "$(GREEN)$(APP_NAME) running — look in the menubar.$(RESET)"

## lint: Run linter (stack-specific — fails closed until a lang-* skill overlays it)
lint:
	@echo "$(CYAN)Running SwiftLint...$(RESET)"
	@command -v swiftlint >/dev/null 2>&1 || { \
		echo "$(RED)  swiftlint is NOT installed — the lint gate cannot run.$(RESET)"; \
		echo "$(RED)  brew install swiftlint. A gate that does not run is a failure.$(RESET)"; \
		exit 1; }
	@swiftlint lint --quiet --strict
	@echo "$(GREEN)Lint clean.$(RESET)"

## typecheck: Run type checker (stack-specific — fails closed until a lang-* skill overlays it)
typecheck: regenerate
	@echo "$(CYAN)Type-checking (swiftc under Swift 6 strict concurrency)...$(RESET)"
	@set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-configuration $(CONFIG) -destination '$(DEST)' \
		-derivedDataPath $(DERIVED_TEST) \
		CODE_SIGNING_ALLOWED=NO \
		build $(FMT)
	@echo "$(GREEN)Type check clean.$(RESET)"

## check-architecture: Enforce VIBE.yaml line limits + module shape (fails closed)
check-architecture:
	@echo "$(CYAN)Checking architecture (line limits + module shape)...$(RESET)"
	@for s in check_architecture.py check_module_rules.py; do \
		if [ ! -f "scripts/$$s" ]; then \
			echo "$(RED)  scripts/$$s is MISSING — the architecture gate$(RESET)"; \
			echo "$(RED)  cannot run. Hard failure, never a skip. Restore it:$(RESET)"; \
			echo "$(RED)  re-run the agentic-skeleton bootstrap.$(RESET)"; \
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

## fix: Auto-fix lint issues (stack-specific)
fix:
	@echo "$(CYAN)Auto-fixing...$(RESET)"
	@echo "$(YELLOW)  (stub — overlay a lang-* skill to fill this in; run 'make help-stack')$(RESET)"

## test: Run tests — VIBE.yaml quality_gates.tests.mode decides (fails closed when required)
test:
	@echo "$(CYAN)Running tests...$(RESET)"
	@MODE=$$(python3 -c "import yaml;d=yaml.safe_load(open('VIBE.yaml'));print((((d or {}).get('quality_gates') or {}).get('tests') or {}).get('mode') or 'deferred')" 2>/dev/null) \
		|| MODE=$$(uv run --with pyyaml python3 -c "import yaml;d=yaml.safe_load(open('VIBE.yaml'));print((((d or {}).get('quality_gates') or {}).get('tests') or {}).get('mode') or 'deferred')" 2>/dev/null) \
		|| MODE=unknown; \
	case "$$MODE" in \
		required) \
			$(MAKE) --no-print-directory regenerate; \
			set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
				-configuration $(CONFIG) -destination '$(DEST)' \
				-derivedDataPath $(DERIVED_TEST) \
				CODE_SIGNING_ALLOWED=NO \
				test $(FMT) ;; \
		deferred|not_applicable) \
			echo "$(YELLOW)  tests.mode='$$MODE' — tests not run, NOT claimed as passing.$(RESET)" ;; \
		*) \
			echo "$(RED)  Could not read quality_gates.tests.mode from VIBE.yaml —$(RESET)"; \
			echo "$(RED)  failing closed.$(RESET)"; \
			exit 1 ;; \
	esac

# ─── Docker ───────────────────────────────────────────────────────────

## docker-build: Build Docker image with version metadata
docker-build:
	@echo "$(CYAN)Building Docker image $(DOCKER_IMAGE)...$(RESET)"
	docker build \
		--build-arg APP_VERSION=$$(git describe --tags --always 2>/dev/null || echo "dev") \
		--build-arg GITHUB_SHA=$$(git rev-parse HEAD 2>/dev/null || echo "unknown") \
		--build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		-t $(DOCKER_IMAGE) .

## docker-run: Run container on port $(PORT)
docker-run:
	@docker run -d --rm --name $(APP_NAME) -p $(PORT):$(PORT) --env-file .env $(DOCKER_IMAGE)
	@echo "$(GREEN)Container running on port $(PORT).$(RESET)"

## docker-stop: Stop container
docker-stop:
	@docker stop $(APP_NAME) 2>/dev/null || true
	@echo "$(GREEN)Container stopped.$(RESET)"

## docker-clean: Remove image and container
docker-clean: docker-stop
	@docker rmi -f $(DOCKER_IMAGE) 2>/dev/null || true
	@echo "$(GREEN)Image removed.$(RESET)"

# ─── Maintenance ──────────────────────────────────────────────────────

## clean: Remove build cache
clean:
	@echo "$(CYAN)Cleaning build cache...$(RESET)"
	@rm -rf build/ dist/ .next/ .turbo/ __pycache__/ .pytest_cache/ .mypy_cache/ .ruff_cache/
	@echo "$(GREEN)Clean.$(RESET)"

## clean-all: Remove build cache + dependencies (destructive — requires confirmation)
clean-all:
	@echo "$(YELLOW)WARNING: This will remove all dependencies and build artifacts.$(RESET)"
	@read -p "Are you sure? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		rm -rf build/ dist/ .next/ .turbo/ __pycache__/ .pytest_cache/ \
			.mypy_cache/ .ruff_cache/ node_modules/ .venv/ uv.lock; \
		echo "$(GREEN)Deep clean complete.$(RESET)"; \
	else \
		echo "$(YELLOW)Cancelled.$(RESET)"; \
	fi

## update: Update dependencies (stack-specific)
update:
	@echo "$(CYAN)Updating dependencies...$(RESET)"
	@echo "$(YELLOW)  (stub — overlay a lang-* skill to fill this in; run 'make help-stack')$(RESET)"

## info: Show project state
info:
	@echo "$(BOLD)$(CYAN)Project Info$(RESET)"
	@echo "──────────────────────────────"
	@echo "  Project: $(APP_NAME)"
	@echo "  Branch:  $$(git branch --show-current 2>/dev/null || echo 'N/A')"
	@echo "  Commit:  $$(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
	@echo "  Tree:    $$(git status --porcelain | wc -l | tr -d ' ') uncommitted changes"
	@echo "  Port:    $(PORT)"

	@echo "Greenfield Makefile targets that print '(stub — overlay a lang-* skill"
	@echo "to fill this in)' need a stack-specific skill to overlay recipe bodies."
	@echo "Pick the skill matching VIBE.yaml::project.stack:"
	@echo ""
	@echo "  $(GREEN)Python / FastAPI$(RESET)        → invoke $(BOLD)/lang-python$(RESET)"
	@echo "  $(GREEN)Next.js / App Router$(RESET)    → invoke $(BOLD)/lang-react$(RESET)"
	@echo "  $(GREEN)Vite SPA$(RESET)                → invoke $(BOLD)/lang-react-spa$(RESET) + $(BOLD)/tool-vite$(RESET)"
	@echo "  $(GREEN)Go$(RESET)                      → invoke $(BOLD)/lang-go$(RESET) (when shipped)"
	@echo "  $(GREEN)MCP server$(RESET)              → invoke $(BOLD)/lang-mcp$(RESET) (when shipped)"
	@echo ""
	@echo "Each lang-* skill provides recipe bodies for: install / dev / build /"
	@echo "start / lint / typecheck / fix / test / update."
	@echo ""
	@echo "Until a lang-* overlay is applied, the stubs do nothing — that is by"
	@echo "design (the skeleton stays stack-agnostic). See"
	@echo "agentic-skeleton/SKILL.md for skill composition guidance."
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

# ─── Privacy (PUBLIC REPO — inviolable) ───────────────────────────────

## claude-probe: Capture ONE real sample of `claude /usage` output
#  Makes exactly one call, so it can't cause a retry storm. The output
#  goes to your terminal only — review it before sharing; it may name
#  your plan. ClaudeUsageTextParser is written against this shape.
claude-probe:
	@echo "$(CYAN)Running one `claude -p /usage` probe...$(RESET)"
	@echo "$(YELLOW)This makes a single call. Review the output before sharing.$(RESET)"
	@echo ""
	@cd "$$TMPDIR" && claude -p "/usage" --output-format json 2>&1 || true
	@echo ""
	@echo "$(CYAN)---$(RESET)"
	@echo "If that printed usage numbers, the CLI fallback can work."
	@echo "Share the SHAPE (labels + where percentages sit) to fix the parser."

## signing-init: Write Local.xcconfig with a STABLE signing identity (gitignored)
#  Ad-hoc signing (the default when Local.xcconfig is absent) binds the
#  keychain item to the build's content hash, which changes every rebuild
#  — reintroducing the exact keychain-prompt bug Robut exists to fix. A
#  real identity makes the code-signing requirement identity-based and
#  therefore STABLE across rebuilds. The identity name is personal data,
#  so it lives ONLY in gitignored Local.xcconfig, never the repo.
signing-init:
	@if [ -f Local.xcconfig ]; then \
		echo "$(YELLOW)Local.xcconfig already exists — leaving it.$(RESET)"; \
	else \
		IDENTITY=$$(security find-identity -v -p codesigning \
			| grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/'); \
		if [ -z "$$IDENTITY" ]; then \
			IDENTITY=$$(security find-identity -v -p codesigning \
				| grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/'); \
		fi; \
		if [ -z "$$IDENTITY" ]; then \
			echo "$(RED)No Developer ID or Apple Development identity found.$(RESET)"; exit 1; fi; \
		TEAM=$$(printf '%s' "$$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$$/\1/'); \
		{ echo "// Local signing — GITIGNORED, never committed."; \
		  echo "// A stable identity so the keychain ACL persists across rebuilds."; \
		  echo "// Regenerate with: make signing-init"; \
		  printf 'CODE_SIGN_IDENTITY = %s\n' "$$IDENTITY"; \
		  printf 'DEVELOPMENT_TEAM = %s\n' "$$TEAM"; \
		  echo "CODE_SIGN_STYLE = Manual"; \
		} > Local.xcconfig; \
		echo "$(GREEN)Wrote Local.xcconfig (stable signing). Run 'make build'.$(RESET)"; \
	fi

## privacy: Scan the worktree for personal data (blocking gate)
privacy:
	@scripts/check-privacy.sh --all

## privacy-init: Create .privacy-denylist.local from this machine's identity
privacy-init:
	@if [ -f .privacy-denylist.local ]; then \
		echo "$(YELLOW).privacy-denylist.local already exists, leaving it alone.$(RESET)"; \
	else \
		{ echo "# Machine-specific strings that must never reach this public repo."; \
		  echo "# Generated by 'make privacy-init'. Gitignored. Edit freely."; \
		  echo ""; \
		  id -un; \
		  git config --get user.name  2>/dev/null || true; \
		  git config --get user.email 2>/dev/null || true; \
		  security find-identity -v -p codesigning 2>/dev/null \
		    | sed -n 's/.*"\(.*\)".*/\1/p' | sed 's/^[^:]*: //'; \
		  security find-identity -v -p codesigning 2>/dev/null \
		    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p'; \
		} | awk 'NF' | sort -u > .privacy-denylist.local; \
		echo "$(GREEN)Wrote .privacy-denylist.local ($$(grep -cv '^#' .privacy-denylist.local) entries).$(RESET)"; \
		echo "$(YELLOW)Review it — add any account UUIDs or hostnames you care about.$(RESET)"; \
	fi

## privacy-history: Scan all of git history for leaked personal data
privacy-history:
	@scripts/check-privacy.sh --history

## hooks: (Re)install the pre-commit framework hooks for this clone
#  NOTE: deliberately does NOT set core.hooksPath — that would shadow
#  .git/hooks/ and silently disable the skeleton's post-commit auto-push.
#  The privacy gate runs as a `local` hook in .pre-commit-config.yaml.
hooks:
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "$(RED)  pre-commit missing — brew install pre-commit$(RESET)"; exit 1; }
	@pre-commit install --hook-type pre-commit --hook-type commit-msg
	@echo "$(GREEN)pre-commit + commit-msg hooks installed (privacy gate active).$(RESET)"

.DEFAULT_GOAL := help

# ─────────────────────────────────────────────────────────────────────
# Release — Developer ID + notarization + Sparkle → GitHub Releases
# ─────────────────────────────────────────────────────────────────────
# Same VERSION and build number `make build` injects. INVARIANT: every
# release is signed with the SAME Developer ID identity (Local.xcconfig).
# A differently-signed update changes the app's designated requirement,
# and macOS re-prompts every user for Robut's OWN keychain item — the
# founding bug, shipped at scale. `archive` refuses to run ad-hoc.
#
# Flow:  make notarize   (archive → export → notarize → staple)
#        make release    (package → appcast → tag → GitHub Release)
RELEASE_DIR    := build/release
ARCHIVE        := $(RELEASE_DIR)/$(APP_NAME).xcarchive
EXPORT_DIR     := $(RELEASE_DIR)/export
EXPORTED_APP   := $(EXPORT_DIR)/$(APP_NAME).app
EXPORT_OPTIONS := $(RELEASE_DIR)/ExportOptions.plist
NOTARY_LOG     := $(RELEASE_DIR)/notary.log
DIST           := dist
ZIP            := $(DIST)/$(APP_NAME)-$(MARKETING).zip
APPCAST        := $(DIST)/appcast.xml
NOTARY_PROFILE ?= robut-notary
GITHUB_REPO    ?= rex/robut
RELEASE_TAG    := v$(MARKETING)
DOWNLOAD_BASE  := https://github.com/$(GITHUB_REPO)/releases/download/$(RELEASE_TAG)
TEAM_ID        := $(shell sed -nE 's/^DEVELOPMENT_TEAM *= *([A-Z0-9]+).*/\1/p' Local.xcconfig 2>/dev/null)
SPARKLE_BIN    := $(shell find $(DERIVED)/SourcePackages/artifacts -type d -path '*parkle*/bin' 2>/dev/null | head -1)

.PHONY: archive export notary-init notarize package appcast release sparkle-keys-init release-clean

release-clean:
	@rm -rf $(RELEASE_DIR) $(DIST)
	@echo "$(GREEN)Release artifacts cleared.$(RESET)"

archive: regenerate
	@if [ -z "$(TEAM_ID)" ]; then \
		echo "$(RED)No Developer ID in Local.xcconfig — run 'make signing-init'.$(RESET)"; \
		echo "$(RED)An ad-hoc build can never be notarized, and would re-prompt every user's keychain.$(RESET)"; \
		exit 1; fi
	@echo "$(CYAN)Archiving $(APP_NAME) $(RELEASE_TAG) (build $(BUILD_NUM)) — Release, universal, Developer ID...$(RESET)"
	@rm -rf $(ARCHIVE)
	@set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED) -archivePath $(ARCHIVE) \
		ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION=$(MARKETING) CURRENT_PROJECT_VERSION=$(BUILD_NUM) \
		archive $(FMT)
	@echo "$(GREEN)Archived → $(ARCHIVE)$(RESET)"

export: archive
	@sed 's/__TEAM_ID__/$(TEAM_ID)/' Config/ExportOptions.template.plist > $(EXPORT_OPTIONS)
	@rm -rf $(EXPORT_DIR)
	@set -o pipefail; $(XCODEBUILD) -exportArchive -archivePath $(ARCHIVE) \
		-exportOptionsPlist $(EXPORT_OPTIONS) -exportPath $(EXPORT_DIR) $(FMT)
	@codesign --verify --deep --strict --verbose=2 "$(EXPORTED_APP)"
	@if codesign -d --entitlements - "$(EXPORTED_APP)" 2>/dev/null | grep -q app-sandbox; then \
		echo "$(RED)App Sandbox is ON — that breaks every provider. See Robut.entitlements.$(RESET)"; exit 1; fi
	@codesign -dvv "$(EXPORTED_APP)" 2>&1 | grep -q "Authority=Developer ID Application" \
		|| { echo "$(RED)Export is not Developer-ID signed.$(RESET)"; exit 1; }
	@codesign -dvv "$(EXPORTED_APP)" 2>&1 | grep -q "flags=.*runtime" \
		|| { echo "$(RED)Hardened runtime missing — notarization would be refused.$(RESET)"; exit 1; }
	@echo "$(GREEN)Exported → $(EXPORTED_APP)$(RESET)"

notary-init:
	@echo "$(BOLD)One-time: notarization credentials → your login keychain as profile '$(NOTARY_PROFILE)'.$(RESET)"
	@echo "You need an APP-SPECIFIC PASSWORD: https://account.apple.com → Sign-In and Security → App-Specific Passwords."
	@echo "Team ID (from Local.xcconfig): $(TEAM_ID)"
	@printf "Apple ID email: "; read APPLE_ID; \
		xcrun notarytool store-credentials "$(NOTARY_PROFILE)" --apple-id "$$APPLE_ID" --team-id "$(TEAM_ID)"
	@echo "$(GREEN)Stored. 'make notarize' uses it; nothing touched the repo.$(RESET)"

notarize: export
	@xcrun notarytool history --keychain-profile "$(NOTARY_PROFILE)" >/dev/null 2>&1 \
		|| { echo "$(RED)No notary credentials — run 'make notary-init' once.$(RESET)"; exit 1; }
	@echo "$(CYAN)Submitting to Apple's notary service (this waits for the verdict)...$(RESET)"
	@rm -f $(RELEASE_DIR)/notary-upload.zip
	@ditto -c -k --keepParent "$(EXPORTED_APP)" $(RELEASE_DIR)/notary-upload.zip
	@xcrun notarytool submit $(RELEASE_DIR)/notary-upload.zip \
		--keychain-profile "$(NOTARY_PROFILE)" --wait 2>&1 | tee $(NOTARY_LOG)
	@grep -q "status: Accepted" $(NOTARY_LOG) || { \
		echo "$(RED)Not accepted. Details: xcrun notarytool log <submission-id> --keychain-profile $(NOTARY_PROFILE)$(RESET)"; exit 1; }
	@xcrun stapler staple "$(EXPORTED_APP)"
	@xcrun stapler validate "$(EXPORTED_APP)"
	@spctl --assess --type execute --verbose=2 "$(EXPORTED_APP)"
	@echo "$(GREEN)Notarized + stapled: $(EXPORTED_APP)$(RESET)"

package:
	@xcrun stapler validate "$(EXPORTED_APP)" >/dev/null 2>&1 \
		|| { echo "$(RED)Not stapled — run 'make notarize' first. Never ship an un-notarized build.$(RESET)"; exit 1; }
	@mkdir -p $(DIST); rm -f $(ZIP)
	@ditto -c -k --keepParent "$(EXPORTED_APP)" $(ZIP)
	@echo "$(GREEN)Packaged → $(ZIP)$(RESET)"

sparkle-keys-init:
	@if [ -z "$(SPARKLE_BIN)" ]; then echo "$(RED)Sparkle tools not found — run 'make build' once.$(RESET)"; exit 1; fi
	@"$(SPARKLE_BIN)/generate_keys"
	@echo "$(YELLOW)Public key above → Robut/Info.plist SUPublicEDKey. The private key stays in your login keychain.$(RESET)"

appcast: package
	@if [ -z "$(SPARKLE_BIN)" ]; then echo "$(RED)Sparkle tools not found — run 'make build' once.$(RESET)"; exit 1; fi
	@"$(SPARKLE_BIN)/generate_appcast" --download-url-prefix "$(DOWNLOAD_BASE)/" $(DIST)
	@grep -q "sparkle:edSignature" $(APPCAST) || { \
		echo "$(RED)Appcast is UNSIGNED — generate_appcast silently skips signing when the app's$(RESET)"; \
		echo "$(RED)SUPublicEDKey is missing or doesn't match the key in your keychain. Not shippable.$(RESET)"; exit 1; }
	@echo "$(GREEN)Appcast (EdDSA-signed) → $(APPCAST)$(RESET)"

release: appcast
	@git diff --quiet && git diff --cached --quiet \
		|| { echo "$(RED)Working tree not clean — commit first.$(RESET)"; exit 1; }
	@awk -v v="$(MARKETING)" '$$0 ~ ("^## \\[" v "\\]") {f=1; next} /^## \[/ {if (f) exit} f' CHANGELOG.md > $(RELEASE_DIR)/notes.md
	@git rev-parse "$(RELEASE_TAG)" >/dev/null 2>&1 || git tag -a "$(RELEASE_TAG)" -m "$(APP_NAME) $(RELEASE_TAG)"
	@git push origin "$(RELEASE_TAG)"
	@gh release create "$(RELEASE_TAG)" $(ZIP) $(APPCAST) \
		--title "$(APP_NAME) $(RELEASE_TAG)" --notes-file $(RELEASE_DIR)/notes.md
	@echo "$(GREEN)Released $(RELEASE_TAG) → https://github.com/$(GITHUB_REPO)/releases/tag/$(RELEASE_TAG)$(RESET)"
