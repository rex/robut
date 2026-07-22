#!/usr/bin/env bash
# check-privacy.sh — the public-repo guard.
#
# Robut is a PUBLIC repository. Nothing that identifies the machine or
# the human running it may ever reach a commit. This script is the gate
# that enforces that, and it is wired into .githooks/pre-commit.
#
# It scans in two layers:
#
#   1. GENERIC PATTERNS (defined here, safe to publish) — home
#      directory paths, email addresses, credential prefixes, JWTs,
#      hardcoded signing identities. These catch the whole *class* of
#      leak without naming anyone.
#
#   2. A LOCAL DENYLIST (.privacy-denylist.local, gitignored) — exact
#      strings specific to this machine: real name, email, team IDs,
#      account UUIDs. Deliberately NOT committed, because a committed
#      list of the secrets you're hiding is itself the leak.
#
# Usage:
#   scripts/check-privacy.sh            # scan staged changes (pre-commit)
#   scripts/check-privacy.sh --all      # scan the entire worktree
#   scripts/check-privacy.sh --history  # scan all of git history

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DENYLIST="$REPO_ROOT/.privacy-denylist.local"
MODE="${1:-staged}"
FAILED=0

red()  { printf '\033[0;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[0;33m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Generic patterns. Each entry is "description|extended-regex".
# These are intentionally person-agnostic so this file is safe to publish.
# ---------------------------------------------------------------------------
PATTERNS=(
  "absolute home directory path|/(Users|home)/[a-zA-Z0-9._-]+"
  "email address|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"
  "Anthropic API key|sk-ant-[a-zA-Z0-9_-]{8,}"
  "OpenAI API key|sk-(proj|svcacct|admin)?-?[a-zA-Z0-9_-]{20,}"
  "GitHub token|gh[pousr]_[a-zA-Z0-9]{16,}"
  "JWT / OAuth token|eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"
  "Slack token|xox[baprs]-[a-zA-Z0-9-]{10,}"
  "AWS access key|AKIA[0-9A-Z]{16}"
  "private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "hardcoded signing team|DEVELOPMENT_TEAM[[:space:]]*[:=][[:space:]]*[A-Z0-9]{10}"
  "hardcoded signing identity|Developer ID Application:[[:space:]]*[A-Za-z]"
)

# Files that are allowed to contain pattern-like text: this scanner itself
# (it necessarily contains the patterns) and the example config.
is_exempt() {
  case "$1" in
    scripts/check-privacy.sh|.privacy-denylist.local|.privacy-denylist.example) return 0 ;;
    *) return 1 ;;
  esac
}

scan_content() {
  local label="$1" content="$2"

  for entry in "${PATTERNS[@]}"; do
    local desc="${entry%%|*}" rx="${entry#*|}"
    local hits
    hits="$(printf '%s' "$content" | grep -nEo "$rx" 2>/dev/null | head -5 || true)"
    if [[ -n "$hits" ]]; then
      red "  ✗ $label — $desc"
      while IFS= read -r h; do [[ -n "$h" ]] && printf '      %s\n' "$h"; done <<<"$hits"
      FAILED=1
    fi
  done

  if [[ -f "$DENYLIST" ]]; then
    while IFS= read -r term; do
      [[ -z "$term" || "$term" == \#* ]] && continue
      if printf '%s' "$content" | grep -qiF "$term" 2>/dev/null; then
        # Never echo the matched secret back — just name the rule.
        red "  ✗ $label — matches local denylist entry #$((++den_idx))"
        FAILED=1
      fi
    done <"$DENYLIST"
  fi
}

# ---------------------------------------------------------------------------

den_idx=0

case "$MODE" in
  staged)
    echo "→ privacy gate: scanning staged changes"
    files="$(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACM || true)"
    [[ -z "$files" ]] && { grn "✓ privacy gate: nothing staged"; exit 0; }
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      is_exempt "$f" && continue
      # Filenames leak too.
      scan_content "$f (path)" "$f"
      # Only scan text blobs.
      if git -C "$REPO_ROOT" show ":$f" 2>/dev/null | head -c 1024 | LC_ALL=C grep -qI . 2>/dev/null; then
        scan_content "$f" "$(git -C "$REPO_ROOT" show ":$f" 2>/dev/null || true)"
      fi
    done <<<"$files"
    ;;

  --all)
    echo "→ privacy gate: scanning worktree"
    scanned=0
    # --cached AND --others: tracked files plus untracked ones. Using
    # --cached alone silently scans NOTHING before the first commit,
    # which reads as a pass. --exclude-standard honors .gitignore, so
    # .privacy-denylist.local itself is never scanned.
    while IFS= read -r f; do
      f="${f#./}"
      [[ -z "$f" ]] && continue
      is_exempt "$f" && continue
      [[ -f "$REPO_ROOT/$f" ]] || continue
      scanned=$((scanned + 1))
      scan_content "$f (path)" "$f"
      if head -c 1024 "$REPO_ROOT/$f" 2>/dev/null | LC_ALL=C grep -qI . 2>/dev/null; then
        scan_content "$f" "$(cat "$REPO_ROOT/$f" 2>/dev/null || true)"
      fi
    done < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard)

    if [[ "$scanned" -eq 0 ]]; then
      red "✗ privacy gate scanned 0 files — refusing to report a pass."
      exit 1
    fi
    echo "  scanned $scanned file(s)"
    ;;

  --history)
    # Scans commit MESSAGES and touched PATHS only. Author/committer
    # identity is deliberately excluded: the repo owner's public git
    # identity is a chosen, published fact (it appears on every commit
    # of every public repo they own), not a leak. Including it here
    # would make this gate permanently red for no security benefit.
    echo "→ privacy gate: scanning git history (messages + paths)"
    while IFS= read -r sha; do
      scan_content "commit $sha (message)" "$(git -C "$REPO_ROOT" log -1 --format='%s%n%b' "$sha")"
      scan_content "commit $sha (paths)" "$(git -C "$REPO_ROOT" show --pretty=format: --name-only "$sha" 2>/dev/null || true)"
    done < <(git -C "$REPO_ROOT" rev-list --all 2>/dev/null || true)
    ;;

  *)
    echo "usage: $0 [--all|--history]" >&2; exit 2 ;;
esac

if [[ "$FAILED" -ne 0 ]]; then
  echo
  red "✗ PRIVACY GATE FAILED — this repo is public."
  ylw "  Fix the findings above. If a match is a false positive, narrow the"
  ylw "  code rather than weakening the gate (e.g. use a relative path, or"
  ylw "  read the value from the environment at runtime)."
  exit 1
fi

grn "✓ privacy gate passed"
