#!/usr/bin/env python3
"""Propose (and optionally delete) orphaned handoff briefs.

A candidate is a brief whose recorded branch no longer exists locally AND
whose age exceeds PRUNE_AFTER_DAYS. The current branch's brief and the legacy
HANDOFF.json slot are never candidates.

Dry-run by default: printing candidates is the whole job unless --apply is
passed (P8 — suggest, never auto-act).

CLI: handoff-prune.py [--apply]
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_hp = _load("handoff_paths", "scripts/handoff_paths.py")
_hl = _load("handoff_list", "scripts/handoff-list.py")

# Deliberately a constant, not a config knob: no demand signal for tuning it
# (cut in spec review 2026-09-03).
PRUNE_AFTER_DAYS = 30


def _age_days(row: dict) -> float:
    """Age from the brief's own timestamp; filesystem mtime only as fallback.
    A brief copied between machines gets a fresh mtime, so the in-file value is
    the durable signal."""
    ts = row.get("timestamp") or ""
    try:
        written = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        try:
            written = datetime.fromtimestamp(Path(row["path"]).stat().st_mtime, timezone.utc)
        except OSError:
            return 0.0
    return (datetime.now(timezone.utc) - written).total_seconds() / 86400.0


def candidates(store: Path, cwd: Path) -> list[dict]:
    out = []
    for row in _hl.collect(store, cwd):
        if row["legacy"] or row["is_current"] or row["branch_exists"]:
            continue
        if not row["branch"]:
            continue  # no recorded branch — cannot prove it is an orphan
        age = _age_days(row)
        if age > PRUNE_AFTER_DAYS:
            out.append({**row, "age_days": round(age, 1)})
    return out


def prune(store: Path, cwd: Path, apply: bool = False) -> list[dict]:
    cands = candidates(store, cwd)
    if not cands:
        print(f"No prunable briefs (orphaned and older than {PRUNE_AFTER_DAYS} days).")
        return cands
    print(f"Prunable briefs — branch gone and older than {PRUNE_AFTER_DAYS} days:\n")
    for c in cands:
        print(f"  {c['key']:<32} branch {c['branch']:<28} {c['age_days']}d old")
    if not apply:
        print("\nDry run — nothing deleted. Re-run with --apply to delete these.")
        return cands
    for c in cands:
        try:
            Path(c["path"]).unlink()
            print(f"deleted {c['path']}")
        except OSError as e:
            print(f"could not delete {c['path']}: {e}", file=sys.stderr)
    return cands


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="actually delete the listed briefs")
    args = ap.parse_args(argv[1:])
    cwd = Path.cwd()
    prune(_hp.handoffs_dir(cwd), cwd, apply=args.apply)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
