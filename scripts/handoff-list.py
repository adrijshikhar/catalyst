#!/usr/bin/env python3
"""Inventory the handoff briefs in the centralized store.

Answers the question READ mode currently makes the model answer by hand:
which briefs exist, which belong to a branch that still exists, and which one
is the current branch's.

CLI: handoff-list.py [--json]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "handoff_paths", ROOT / "scripts" / "handoff_paths.py")
_hp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_hp)

LEGACY_STEM = "HANDOFF"


def _git(args: list[str], cwd: Path) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                           text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def local_branches(cwd: Path) -> set[str]:
    out = _git(["branch", "--list", "--format=%(refname:short)"], cwd)
    if out is None:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def current_branch(cwd: Path) -> str:
    return _git(["branch", "--show-current"], cwd) or ""


def collect(store: Path, cwd: Path) -> list[dict]:
    """One row per brief. Unreadable briefs are listed with empty fields rather
    than skipped — a brief you cannot parse is exactly what you want to see."""
    live = local_branches(cwd)
    cur = current_branch(cwd)
    rows: list[dict] = []
    stores = [store]
    if store == _hp.handoffs_dir(cwd):
        stores.append(_hp.legacy_dir(store))
    for f in sorted(f for directory in stores for f in directory.glob("*.json")):
        try:
            obj = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, ValueError):
            obj = {}
        branch = ((obj.get("state") or {}).get("branch") or "")
        rows.append({
            "key": f.stem,
            "path": str(f),
            "branch": branch,
            "timestamp": obj.get("timestamp", ""),
            "branch_exists": bool(branch) and branch in live,
            "is_current": bool(branch) and branch == cur,
            "legacy": f.stem == LEGACY_STEM,
        })
    return rows


def render(rows: list[dict]) -> str:
    if not rows:
        return "No handoff briefs in the store.\n"
    out = ["Handoff briefs", "",
           f"{'KEY':<32} {'BRANCH':<28} {'BRANCH?':<9} {'WRITTEN':<21} NOTE"]
    for r in rows:
        note = []
        if r["is_current"]:
            note.append("current branch")
        if r["legacy"]:
            note.append("legacy slot")
        if not r["branch_exists"] and not r["legacy"]:
            note.append("orphan")
        out.append(f"{r['key']:<32} {r['branch'] or '—':<28} "
                   f"{('yes' if r['branch_exists'] else 'no'):<9} "
                   f"{r['timestamp'] or '—':<21} {', '.join(note)}\n  {r['path']}")
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv[1:])
    cwd = Path.cwd()
    rows = collect(_hp.handoffs_dir(cwd), cwd)
    print(json.dumps(rows, indent=2) if args.json else render(rows), end="" if args.json else "")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
