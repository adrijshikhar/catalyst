#!/usr/bin/env python3
"""Deterministic CI-side grader for committed eval snapshots.

Reads skills/<name>/evals/evals.json + skills/<name>/evals/snapshots/results.json,
re-applies each eval's deterministic assertions to the committed transcript text,
and reports pass@1 / pass@3 + median/min/max/stdev. Never calls a model.

Usage:
    eval-grade.py [--skill <name>] [--check-fresh]
Exit non-zero if a regression eval's pass^3 < 1.00 or a declared snapshot is missing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_CONTAINS_RE = re.compile(r"'([^']+)'|\"([^\"]+)\"")


def grade_assertion(assertion: str, transcript_text: str) -> bool:
    """Deterministic subset: 'X exists' and contains-'literal' checks.

    Conservative: an assertion we cannot grade deterministically returns False
    and should be tagged grader:model upstream (none today).

    NOTE: this transcript-grep grader is being superseded by the artifact-aware
    grader (see eval-grader-redesign spec). The fixes here are the mechanical
    ones flagged in review: anchor the 'exists' check to the end of the
    assertion, and require ALL quoted needles to be present (not just the
    first)."""
    stripped = assertion.rstrip().rstrip(".")
    # Anchored 'exists': the assertion must END with 'exists' so phrases like
    # "the file already exists in the repo" don't false-trigger.
    if stripped.lower().endswith(" exists"):
        target = stripped[: -len(" exists")].strip().strip("`")
        return target in transcript_text
    needles = [m.group(1) or m.group(2) for m in _CONTAINS_RE.finditer(assertion)]
    if needles:
        return all(n in transcript_text for n in needles)
    return False


def summarize(run_results: list[float]) -> dict:
    n = len(run_results)
    return {
        "n": n,
        "pass_at_1": 1.0 if run_results and run_results[0] >= 1.0 else 0.0,
        "pass_at_3": 1.0 if any(r >= 1.0 for r in run_results[:3]) else 0.0,
        "pass_caret_3": 1.0 if n >= 3 and all(r >= 1.0 for r in run_results[:3]) else 0.0,
        "mean": statistics.fmean(run_results) if run_results else 0.0,
        "median": statistics.median(run_results) if run_results else 0.0,
        "min": min(run_results) if run_results else 0.0,
        "max": max(run_results) if run_results else 0.0,
        "stdev": statistics.pstdev(run_results) if len(run_results) > 1 else 0.0,
    }


def skill_md_sha256(skill_dir: Path) -> str:
    md = skill_dir / "SKILL.md"
    if not md.exists():
        return ""
    return hashlib.sha256(md.read_bytes()).hexdigest()


def grade_skill(skill_dir: Path, errors: list[str], *, check_fresh: bool) -> bool:
    """Grade one skill's committed snapshot. Returns True if a snapshot was
    found and graded, False if absent (skill has evals but no snapshot yet)."""
    evals_json = skill_dir / "evals" / "evals.json"
    snap_dir = skill_dir / "evals" / "snapshots"
    if not evals_json.exists():
        return False
    spec = json.loads(evals_json.read_text())
    results_path = snap_dir / "results.json"
    if not results_path.exists():
        # No snapshot yet — warn (not fatal) so a skill can land before its snapshot.
        print(f"WARN {skill_dir.name}: no snapshot (run scripts/eval-run.py locally)")
        return False
    snapshot = json.loads(results_path.read_text())
    if check_fresh:
        stored = snapshot.get("meta", {}).get("skill_md_sha256", "")
        if stored and stored != skill_md_sha256(skill_dir):
            print(f"WARN {skill_dir.name}: snapshot stale (SKILL.md changed); regenerate")
    for ev in spec.get("evals", []):
        runs = snapshot.get("evals", {}).get(str(ev["id"]), {}).get("runs", [])
        if not runs:
            errors.append(f"{skill_dir.name} eval {ev['id']}: no snapshot runs")
            continue
        run_scores: list[float] = []
        for run in runs:
            transcript = run.get("transcript_text", "")
            ok = all(grade_assertion(a, transcript) for a in ev["assertions"])
            run_scores.append(1.0 if ok else 0.0)
        stats = summarize(run_scores)
        print(
            f"{skill_dir.name}/{ev['name']}: pass@3={stats['pass_at_3']:.2f} "
            f"median={stats['median']:.2f} stdev={stats['stdev']:.2f} n={stats['n']}"
        )
        if ev.get("category") == "regression" and stats["pass_caret_3"] < 1.0:
            errors.append(f"{skill_dir.name} regression '{ev['name']}': pass^3 < 1.00")
    return True


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", default=None)
    ap.add_argument("--check-fresh", action="store_true")
    args = ap.parse_args(argv[1:])
    errors: list[str] = []
    skills = [ROOT / "skills" / args.skill] if args.skill else sorted((ROOT / "skills").glob("*/"))
    with_evals = 0
    graded = 0
    for skill_dir in skills:
        if (skill_dir / "evals").is_dir():
            with_evals += 1
            if grade_skill(skill_dir, errors, check_fresh=args.check_fresh):
                graded += 1
    if errors:
        print("eval-grade: FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    # Explicit enforcement summary — a green run with 0 snapshots enforces
    # NOTHING; say so plainly so CI logs aren't misread as "evals passed".
    if graded == 0 and with_evals > 0:
        print(
            f"eval-grade: OK (NOT ENFORCED — 0/{with_evals} skills have snapshots; "
            "thresholds are dormant until snapshots are seeded via scripts/eval-run.py)"
        )
    else:
        print(f"eval-grade: OK ({graded}/{with_evals} skills graded against committed snapshots)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
