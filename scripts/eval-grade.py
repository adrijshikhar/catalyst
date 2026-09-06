#!/usr/bin/env python3
"""Deterministic CI-side grader for committed eval snapshots (Lane A).

Reads skills/<name>/evals/evals.json + skills/<name>/evals/snapshots/results.json
and re-applies each eval's assertions to the captured transcript AND the files the
run wrote. Never calls a model. Reports pass@1 / pass@3 / pass^3 + median/min/max/
stdev per eval, and counts assertions the grammar cannot grade (they count as
failed, never as passed).

Assertion grammar (prose, deterministic — anything else is UNGRADED = fail):
  <path> exists [in the working directory]        a captured file whose path ends with <path>
  ... NOT written / does NOT exist / No ... was written ... <path>
                                                  no captured file ends with any <path> token
  `<cmd>` exits 0                                 cmd run against the captured files (scripts/ → this checkout)
  <path> passes 'bash -n' ...                     bash -n on the captured file
  ... 'needle' ... "needle" ...                   all needles in transcript+files; with " OR " /
                                                  "at least one of" any needle suffices

Usage:
    eval-grade.py [--skill <name>] [--enforce]
--enforce: missing or stale snapshot, capability pass@3 < 0.90 or regression
pass^3 < 1.00 exit non-zero. Without it, those are WARN lines (seeding phase).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_NEEDLE_RE = re.compile(r"'([^']+)'|\"([^\"]+)\"")
_PATH_RE = re.compile(r"[\w./-]+\.(?:json|md|sh|txt|yaml|yml|py|ts|tsx|js|toml)\b")
_CMD_RE = re.compile(r"`([^`]+)`\s+exits\s+0")
_NEG_RE = re.compile(r"\bNOT\b|\bnot exist|\bNo session checkpoint|\bnot created|\babsence of", re.I)
CAP_THRESHOLD = 0.90


def _corpus(transcript: str, files: dict[str, str]) -> str:
    return transcript + "\n" + "\n".join(f"{p}\n{c}" for p, c in files.items())


def _file_matches(token: str, files: dict[str, str]) -> bool:
    t = token.strip().strip("`").lstrip("./")
    return any(p == t or p.endswith("/" + t) or p.endswith(t) for p in files)


def _run_cmd(cmd: str, files: dict[str, str]) -> bool:
    with tempfile.TemporaryDirectory(prefix="catalyst-grade-") as d:
        ws = Path(d)
        for rel, content in files.items():
            (ws / rel).parent.mkdir(parents=True, exist_ok=True)
            (ws / rel).write_text(content, encoding="utf-8")
        os.symlink(ROOT / "scripts", ws / "scripts")
        proc = subprocess.run(cmd, shell=True, cwd=ws, capture_output=True, text=True, timeout=60)
        return proc.returncode == 0


def _is_json(text: str) -> bool:
    try:
        json.loads(text); return True
    except Exception:
        return False


def _dotted(obj, path: str):
    cur = obj
    for part in path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def _run_cmd_out(cmd: str, files: dict[str, str]) -> str | None:
    with tempfile.TemporaryDirectory(prefix="catalyst-grade-") as d:
        ws = Path(d)
        for rel, content in files.items():
            (ws / rel).parent.mkdir(parents=True, exist_ok=True)
            (ws / rel).write_text(content, encoding="utf-8")
        os.symlink(ROOT / "scripts", ws / "scripts")
        try:
            proc = subprocess.run(cmd, shell=True, cwd=ws, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return None
        return proc.stdout if proc.returncode == 0 else None


def grade_assertion(assertion: str, transcript: str, files: dict[str, str] | None = None) -> bool | None:
    """True/False when gradable; None when the grammar cannot decide."""
    files = files or {}
    a = assertion.strip().rstrip(".")
    low = a.lower()
    m = _CMD_RE.search(a)
    if m:
        return _run_cmd(m.group(1), files)
    if "bash -n" in low:
        paths = _PATH_RE.findall(a)
        return bool(paths) and _file_matches(paths[0], files) and _run_cmd(f"bash -n {paths[0].lstrip('./')}", files)
    if _NEG_RE.search(a):
        paths = [p for p in _PATH_RE.findall(a) if not p.startswith("scripts/")]
        if paths:
            return not any(_file_matches(p, files) for p in paths)
        return None
    # JSON field: "Brief state.branch is feat/jwt-expiry" / "Brief state.next_acceptance_check mentions the 6/6 ..."
    mj = re.match(r"^(?:the\s+)?(?:written\s+)?brief\s+([\w.]+)\s+(is|mentions|names|contains)\s+(.+)$", a, re.I)
    if mj:
        field, verb, rest = mj.group(1), mj.group(2).lower(), mj.group(3)
        briefs = [json.loads(c) for pth, c in files.items() if pth.endswith(".json") and "/handoffs/" in pth and _is_json(c)]
        if not briefs:
            return False
        vals = [_dotted(b, field) for b in briefs]
        needles = [x or y for x, y in _NEEDLE_RE.findall(rest)] or _PATH_RE.findall(rest) or re.findall(r"[\w/.<>=()-]{3,}", rest.split("(")[0])
        if verb == "is":
            target = rest.strip().strip("`'\"")
            return any(str(v) == target for v in vals)
        return any(any(n in json.dumps(v) for n in needles) for v in vals if v is not None)
    # positive path presence: "Brief was written to <path>", "<file> was created at <path>"
    mp = re.search(r"\b(?:written to|created at|saved to|exists at)\s+([\w./-]+\.(?:json|md|sh|txt))", a, re.I)
    if mp and not _NEG_RE.search(a):
        return _file_matches(mp.group(1), files)
    # rendered output: "The rendered output of `cmd` contains the next acceptance check" -> run cmd, check needles/prose keywords in stdout
    mr = re.search(r"rendered output of `([^`]+)`\s+(?:contains|includes|mentions)\s+(.+)$", a, re.I)
    if mr:
        out = _run_cmd_out(mr.group(1), files)
        needles = [x or y for x, y in _NEEDLE_RE.findall(mr.group(2))]
        return out is not None and (all(n in out for n in needles) if needles else len(out) > 0)
    # Chat prose: "Chat response names tier 2 (branch) as ..." -> case-insensitive phrase in transcript
    mc = re.match(r"^chat response (?:names|mentions|lists|states|says)\s+(.+?)(?:\s+\(|\s+as\b|$)", a, re.I)
    if mc and not _NEEDLE_RE.search(a):
        phrase = mc.group(1).strip().strip("`")
        return phrase.lower() in transcript.lower()
    stripped = re.sub(r"\s+in the working directory$", "", low)
    if stripped.endswith(" exists"):
        target = a[: len(stripped) - len(" exists")].strip().strip("`")
        target = re.sub(r"\s+in the working directory$", "", target, flags=re.I)
        return _file_matches(target, files) or (target in transcript)
    paths = _PATH_RE.findall(a)
    subject = paths[0] if paths and _file_matches(paths[0], files) else None
    needles = [x or y for x, y in _NEEDLE_RE.findall(a)]
    if subject and not needles and len(paths) > 1:
        needles = [p for p in paths[1:]]  # "<file> names src/utils/logger.ts"
    if subject and needles:
        content = next(c for pth, c in files.items() if _file_matches(subject, {pth: c}))
        any_of = " or " in low or "at least one of" in low
        hits = [n in content for n in needles]
        return any(hits) if any_of else all(hits)
    if needles:
        corpus = _corpus(transcript, files)
        any_of = " or " in low or "at least one of" in low
        hits = [n in corpus for n in needles]
        return any(hits) if any_of else all(hits)
    return None


def summarize(run_results: list[float]) -> dict:
    n = len(run_results)
    return {
        "n": n,
        "pass_at_1": 1.0 if run_results and run_results[0] >= 1.0 else 0.0,
        "pass_at_3": 1.0 if any(r >= 1.0 for r in run_results[:3]) else 0.0,
        "pass_caret_3": 1.0 if n >= 3 and all(r >= 1.0 for r in run_results[:3]) else 0.0,
        "median": statistics.median(run_results) if run_results else 0.0,
        "min": min(run_results) if run_results else 0.0,
        "max": max(run_results) if run_results else 0.0,
        "stdev": statistics.pstdev(run_results) if len(run_results) > 1 else 0.0,
    }


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ""


def grade_skill(skill_dir: Path, errors: list[str], warns: list[str], *, enforce: bool) -> dict | None:
    evals_json = skill_dir / "evals" / "evals.json"
    if not evals_json.exists():
        return None
    spec = json.loads(evals_json.read_text())
    snap_dir = skill_dir / "evals" / "snapshots"
    results = snap_dir / "results.json"
    if not results.exists():
        (errors if enforce else warns).append(f"{skill_dir.name}: no snapshot (run scripts/eval-run.py locally)")
        return None
    snap = json.loads(results.read_text())
    meta = snap.get("meta", {})
    stale = []
    if meta.get("skill_md_sha256") and meta["skill_md_sha256"] != _sha(skill_dir / "SKILL.md"):
        stale.append("SKILL.md")
    if meta.get("evals_json_sha256") and meta["evals_json_sha256"] != _sha(evals_json):
        stale.append("evals.json")
    if stale:
        (errors if enforce else warns).append(f"{skill_dir.name}: snapshot stale ({', '.join(stale)} changed since seed); regenerate")
    report = {"skill": skill_dir.name, "model": meta.get("model"), "evals": []}
    for ev in spec.get("evals", []):
        if not isinstance(ev.get("prompt"), str):
            continue
        entry = snap.get("evals", {}).get(str(ev["id"]))
        if not entry:
            (errors if enforce else warns).append(f"{skill_dir.name}/{ev['name']}: declared but not in snapshot")
            continue
        per_run, ungraded = [], 0
        for run in entry.get("runs", []):
            transcript = run.get("transcript_text") or ""
            if not transcript and run.get("transcript_file"):
                tf = snap_dir / run["transcript_file"]
                transcript = tf.read_text(encoding="utf-8", errors="replace") if tf.exists() else ""
            files = run.get("files") or {}
            verdicts = [grade_assertion(a, transcript, files) for a in ev.get("assertions", [])]
            ungraded += sum(1 for v in verdicts if v is None)
            per_run.append(sum(1 for v in verdicts if v is True) / max(1, len(verdicts)))
        stats = summarize(per_run)
        cat = ev.get("category", "capability")
        report["evals"].append({"id": ev["id"], "name": ev["name"], "category": cat, "ungraded_assertions": ungraded // max(1, len(entry.get("runs", []))), **stats})
        line = f"{skill_dir.name}/{ev['name']} [{cat}]: pass@1={stats['pass_at_1']:.0f} pass@3={stats['pass_at_3']:.0f} pass^3={stats['pass_caret_3']:.0f} median={stats['median']:.2f} min={stats['min']:.2f} max={stats['max']:.2f} stdev={stats['stdev']:.2f}"
        if ungraded:
            line += f"  ungraded={ungraded // max(1, len(entry.get('runs', [])))}"
        print(line)
        if cat == "regression" and stats["pass_caret_3"] < 1.0:
            (errors if enforce else warns).append(f"{skill_dir.name} regression '{ev['name']}': pass^3 < 1.00")
    caps = [e for e in report["evals"] if e["category"] == "capability"]
    if caps:
        rate = sum(e["pass_at_3"] for e in caps) / len(caps)
        report["capability_pass_at_3"] = rate
        print(f"{skill_dir.name}: capability pass@3 = {rate:.2f} over {len(caps)} evals (threshold {CAP_THRESHOLD}); model={meta.get('model')}")
        if rate < CAP_THRESHOLD:
            (errors if enforce else warns).append(f"{skill_dir.name}: capability pass@3 {rate:.2f} < {CAP_THRESHOLD}")
    return report


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill")
    ap.add_argument("--enforce", action="store_true")
    ap.add_argument("--check-fresh", action="store_true", help="alias of --enforce (compat)")
    args = ap.parse_args(argv[1:])
    enforce = args.enforce or args.check_fresh
    skills = [ROOT / "skills" / args.skill] if args.skill else sorted(p for p in (ROOT / "skills").iterdir() if p.is_dir())
    errors: list[str] = []; warns: list[str] = []; graded = 0; with_evals = 0
    for sd in skills:
        if (sd / "evals" / "evals.json").exists():
            with_evals += 1
        if grade_skill(sd, errors, warns, enforce=enforce):
            graded += 1
    for w in warns:
        print(f"WARN {w}")
    if errors:
        print("eval-grade: FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    if graded == 0:
        print(f"eval-grade: OK (NOT ENFORCED — 0/{with_evals} skills have snapshots; seed via scripts/eval-run.py)")
    else:
        print(f"eval-grade: OK ({graded}/{with_evals} skills graded{'; thresholds ENFORCED' if enforce else '; thresholds reported, not enforced'})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
