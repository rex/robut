#!/usr/bin/env python3
"""check_phony.py — every .PHONY name in the Makefile must have a rule.

make treats a .PHONY name with no rule as a successful no-op. When a
scripted rewrite in c89f469 deleted eight gate recipes by accident, their
names survived in .PHONY, so `make check-if-the-agent-can-consider-this-
task-completed` exited 0 having checked nothing, and `validate` silently
skipped `check-skills` for six weeks (rex/robut#1). A deleted gate must
fail loudly, not pass silently — that is all this checks.

Usage: python3 scripts/check_phony.py [Makefile]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# A rule head: `name:` or `name::`, but not a `name := value` assignment.
RULE = re.compile(r"^([A-Za-z0-9_.%/-]+)\s*::?(?!=)", re.MULTILINE)


def phony_names(text: str) -> list[str]:
    """Every name declared in any `.PHONY:` line, following `\\` continuations."""
    names: list[str] = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith(".PHONY:"):
            chunk = line[len(".PHONY:") :]
            while chunk.rstrip().endswith("\\") and index + 1 < len(lines):
                names += chunk.rstrip()[:-1].split()
                index += 1
                chunk = lines[index]
            names += chunk.split()
        index += 1
    return names


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "Makefile")
    text = path.read_text(encoding="utf-8")
    rules = {match.group(1) for match in RULE.finditer(text)}
    declared = phony_names(text)
    missing = sorted({name for name in declared if name not in rules})
    if missing:
        print(
            f"✗ check_phony: {len(missing)} .PHONY name(s) in {path} have no rule — "
            "make would report them as passing while doing nothing:"
        )
        for name in missing:
            print(f"  ✗ {name}")
        return 1
    print(
        f"✓ check_phony: all {len(set(declared))} .PHONY targets in {path} have rules."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
