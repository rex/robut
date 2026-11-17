#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""check_version_bumped.py — gate that blocks commits without a version bump.

Wired into:
  - `make validate` (skeleton Makefile target)
  - `.pre-commit-config.yaml` (humans)
  - `auto-commit.sh` (Claude Code autonomous commits)

Rules enforced:
  1. VERSION file exists and contains a semver string.
  2. VERSION differs from HEAD's VERSION (unless HEAD doesn't exist —
     bootstrap exemption for the first commit).
  3. CHANGELOG.md has a `## [<NEW_VERSION>] — ` header matching the
     current VERSION.

Lockstep VERSION (lang-swift-apple `references/distribution.md`):
`MAJOR=<n>` + `MINOR_BASE=<n>` lines, with the marketing minor derived
from the commit count, so the bump happens on every commit by
construction. The gate instead requires both fields to be integers and
the `.githooks/pre-commit` auto-bumper to be active (core.hooksPath =
.githooks, hook executable). CI checkouts never install hooks, so there
only the format is checked.

Exit codes:
  0  ok
  1  version not bumped / lockstep auto-bumper inactive
  2  changelog missing or mismatched
  3  malformed version
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


_TTY = sys.stderr.isatty() and "NO_COLOR" not in os.environ
_R = "\033[31m" if _TTY else ""
_G = "\033[32m" if _TTY else ""
_X = "\033[0m" if _TTY else ""

SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
LOCKSTEP_RE = re.compile(r"^MAJOR=", re.M)


def fail(msg: str, code: int) -> None:
    print(f"{_R}✗ version-gate:{_X} {msg}", file=sys.stderr)
    sys.exit(code)


def _git_show_version(ref: str) -> str | None:
    """Return VERSION contents at the given git ref, or None if ref/file missing."""
    show = subprocess.run(
        ["git", "show", f"{ref}:VERSION"],
        capture_output=True, text=True, check=False,
    )
    if show.returncode != 0:
        return None
    return show.stdout.strip()


def _git_repo_ok() -> bool:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            capture_output=True, check=False,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def head_version() -> str | None:
    """Return HEAD's VERSION (pre-commit comparison: working-tree vs HEAD)."""
    if not _git_repo_ok():
        return None
    head_check = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        capture_output=True, check=False,
    )
    if head_check.returncode != 0:
        return None  # bootstrap exemption: no HEAD yet
    return _git_show_version("HEAD")


def parent_version() -> str | None:
    """Return HEAD~1's VERSION (post-commit / CI comparison: HEAD vs parent).

    In CI the checkout puts working-tree IN SYNC with HEAD — comparing
    them always says "unchanged". The right comparison there is HEAD vs
    HEAD~1. Bootstrap exemption: parent doesn't exist on the very first
    commit.
    """
    if not _git_repo_ok():
        return None
    parent_check = subprocess.run(
        ["git", "rev-parse", "HEAD~1"],
        capture_output=True, check=False,
    )
    if parent_check.returncode != 0:
        return None  # bootstrap exemption: only one commit so far
    return _git_show_version("HEAD~1")


def check_lockstep(text: str) -> int:
    """Lockstep VERSION: integer fields + an active auto-bumper hook."""
    fields = dict(re.findall(r"^(MAJOR|MINOR_BASE)=\s*(\S*)\s*$", text, re.M))
    if not all(fields.get(k, "").isdigit() for k in ("MAJOR", "MINOR_BASE")):
        fail(f"lockstep VERSION needs integer MAJOR= and MINOR_BASE= lines "
             f"(found {fields})", 3)
    label = f"lockstep MAJOR={fields['MAJOR']} MINOR_BASE={fields['MINOR_BASE']}"
    if os.environ.get("CI", "").lower() == "true":
        print(f"{_G}✓ version-gate:{_X} {label} (CI: hooks are not "
              "installed, format checked only)")
        return 0
    hooks = subprocess.run(["git", "config", "--get", "core.hooksPath"],
                           capture_output=True, text=True, check=False)
    hook = Path(".githooks/pre-commit")
    if hooks.stdout.strip() != ".githooks" or not os.access(hook, os.X_OK):
        fail(f"{label}, but the .githooks/pre-commit auto-bumper is not "
             "active. Run: git config core.hooksPath .githooks", 1)
    print(f"{_G}✓ version-gate:{_X} {label}; .githooks/pre-commit "
          "auto-bumper active")
    return 0


def main() -> int:
    version_file = Path("VERSION")
    if not version_file.is_file():
        fail("VERSION file missing at repo root. Run: scripts/bump_version.py patch", 1)

    current = version_file.read_text().strip()
    if LOCKSTEP_RE.search(current):
        return check_lockstep(current)
    if not SEMVER_RE.match(current):
        fail(f"VERSION is not semver: '{current}'", 3)

    # In CI, the checkout puts working-tree IN SYNC with HEAD, so comparing
    # them always says "unchanged" and the gate trips on every release.
    # Compare HEAD vs HEAD~1 instead when CI=true (GitHub Actions / Gitea
    # Actions / most CI runners set this automatically).
    in_ci = os.environ.get("CI", "").lower() == "true"
    prev = parent_version() if in_ci else head_version()
    if prev is not None and prev == current:
        fail(
            f"VERSION unchanged ({current}). Bump before committing.\n"
            "    Run: make bump-patch | bump-minor | bump-major",
            1,
        )

    changelog = Path("CHANGELOG.md")
    if not changelog.is_file():
        fail("CHANGELOG.md missing. bump_version.py creates it — re-run the bump.", 2)

    changelog_text = changelog.read_text()
    # Match `## [X.Y.Z] — ` or `## [X.Y.Z] -` at any line
    pattern = rf"^## \[{re.escape(current)}\][[:space:]]+[—-]"
    # Python's re doesn't support [:space:] — use \s
    pattern = pattern.replace("[[:space:]]+", r"\s+")
    if not re.search(pattern, changelog_text, re.MULTILINE):
        fail(
            f"CHANGELOG.md has no entry for version {current}. "
            f"Expected: '## [{current}] — <date> — Agent: <name>'",
            2,
        )

    print(f"{_G}✓ version-gate:{_X} VERSION={current}, CHANGELOG has matching entry")
    return 0


if __name__ == "__main__":
    sys.exit(main())
