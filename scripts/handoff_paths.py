#!/usr/bin/env python3
"""Resolve the centralized handoffs directory + load the brief schema.

The handoffs dir is repo-wide: anchored at the MAIN worktree (parent of the
shared git-common-dir), so every linked worktree shares one store keyed by
branch. Mirrors scripts/handoff-dir.sh (bash) — kept in sync by
tests/test_handoff_paths.py.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "skills" / "handoff" / "brief.schema.json"


def _git(args: list[str], cwd: Path) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def handoffs_dir(cwd: Path | None = None) -> Path:
    """Centralized .claude/handoffs dir. Falls back to <cwd>/.claude/handoffs
    when not in a git repo or git-common-dir is unusable."""
    cwd = Path(cwd or Path.cwd())
    common = _git(["rev-parse", "--git-common-dir"], cwd)
    if common:
        common_path = (cwd / common).resolve() if not Path(common).is_absolute() else Path(common)
        # main checkout = parent of the shared .git dir
        if common_path.name == ".git":
            return common_path.parent / ".claude" / "handoffs"
    return cwd / ".claude" / "handoffs"


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


if __name__ == "__main__":
    import sys
    # Optional path arg mirrors handoff-dir.sh's $1; default to cwd.
    _args = [a for a in sys.argv[1:] if a != "--dir"]
    print(handoffs_dir(_args[0] if _args else None))
