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
_NEG_RE = re.compile(r"\bNOT\s+(?:written|created|read|exist|auto-read|silently|used|be used)|\bdoes\s+NOT\s+exist|\bNo\s+[\w\s]*?\bwas\s+written|\bnot created|\babsence of", re.I)
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


def _assistant_text(transcript: str) -> str:
    """What the agent said: assistant text blocks + the final result. Tool output is
    evidence of what the tools did, never of what the agent claimed."""
    out = []
    for line in transcript.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "assistant":
            for c in ev.get("message", {}).get("content", []):
                if c.get("type") == "text":
                    out.append(c.get("text", ""))
        elif ev.get("type") == "result":
            out.append(str(ev.get("result", "")))
    # unit-test fixtures and legacy snapshots are plain text, not stream-json
    return "\n".join(out) if out else transcript


def _tool_uses(transcript: str, names: set[str]) -> int:
    n = 0
    for line in transcript.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "assistant":
            for c in ev.get("message", {}).get("content", []):
                if c.get("type") == "tool_use" and c.get("name") in names:
                    n += 1
    return n


def _subject_content(token: str, files: dict[str, str]) -> str | None:
    """Content of the named file, or the concatenation of files under a directory token (ends with /)."""
    tok = token.strip().strip("`").lstrip("./")
    if tok.endswith("/"):
        parts = [c for pth, c in files.items() if pth.startswith(tok) or ("/" + tok) in ("/" + pth)]
        return "\n".join(parts) if parts else None
    for pth, c in files.items():
        if _file_matches(tok, {pth: c}):
            return c
    return None


_TOKEN_RE = re.compile(r"(?<![\w/])(\.?[\w./-]*[\w-]\.(?:json|md|sh|txt|yaml|yml|py|ts|tsx|js|toml)|\.?[\w.-]+/(?:[\w.-]+/)*)(?![\w])")
_NEG_RE = re.compile(r"(?-i:\bNOT\b)|\bdoes not (?:exist|contain)\b|(?-i:\bNo\b).*?\bwas written\b|\bnot created\b|\bnever written\b", re.I)
_DISPATCH_RE = re.compile(r"(?:agent|task) tool dispatch occurs (\d+|once|twice|zero) times?|dispatch occurs (once|twice|\d+ times?)", re.I)
_LINES_RE = re.compile(r"^([\w./-]+)\s+is\s+(\d+)\s+lines?\s+or\s+fewer", re.I)
_WORDS = {"once": 1, "twice": 2, "zero": 0}


def grade_assertion(assertion: str, transcript: str, files: dict[str, str] | None = None) -> bool | None:
    """True/False when gradable; None when the grammar cannot decide (counts as failed)."""
    files = files or {}
    a = assertion.strip().rstrip(".")
    low = a.lower()
    needles = [x or y for x, y in _NEEDLE_RE.findall(a)]
    tokens = [tk for tk in _TOKEN_RE.findall(a) if not tk.startswith("scripts/")]
    subject = next((tk for tk in tokens if _subject_content(tk, files) is not None), None)
    any_of = " or " in low or "at least one of" in low

    m = _CMD_RE.search(a)
    if m:
        return _run_cmd(m.group(1), files)
    if "bash -n" in low and tokens:
        return _subject_content(tokens[0], files) is not None and _run_cmd(f"bash -n {tokens[0].lstrip('./')}", files)
    m = _DISPATCH_RE.search(a)
    if m:
        raw = (m.group(1) or m.group(2) or "").split()[0].lower()
        want = _WORDS.get(raw, int(raw) if raw.isdigit() else None)
        return want is not None and _tool_uses(transcript, {"Task", "Agent"}) == want
    m = _LINES_RE.match(a)
    if m:
        content = _subject_content(m.group(1), files)
        return content is not None and len(content.rstrip("\n").splitlines()) <= int(m.group(2))
    m = re.match(r"^(?:the\s+)?(?:written\s+|recovered\s+)?brief\s+([\w.]+)\s+(is|mentions|names|contains)\s+(.+)$", a, re.I)
    if m:
        field, verb, rest = m.group(1), m.group(2).lower(), m.group(3)
        briefs = [json.loads(c) for pth, c in files.items() if pth.endswith(".json") and "handoffs/" in pth and _is_json(c)]
        if not briefs:
            return False
        vals = [_dotted(b, field) for b in briefs]
        if verb == "is":
            return any(str(v) == rest.strip().strip("`'\"") for v in vals)
        ns = needles or _TOKEN_RE.findall(rest) or re.findall(r"[\w/.<>=()-]{3,}", rest.split("(")[0])
        hits = [n in json.dumps(v) for v in vals if v is not None for n in ns]
        return any(hits) if any_of else (bool(hits) and all(n in json.dumps(v) for v in vals if v is not None for n in ns))
    m = re.search(r"\b(?:written to|created at|saved to|overwritten at|exists at)\s+([\w./-]+\.(?:json|md|sh|txt))", a, re.I)
    if m and not _NEG_RE.search(a):
        return _file_matches(m.group(1), files)
    m = re.search(r"rendered output of `([^`]+)`\s+(?:contains|includes|mentions)\s+(.+)$", a, re.I)
    if m:
        out = _run_cmd_out(m.group(1), files)
        return out is not None and (all(n in out for n in needles) if needles else len(out) > 0)
    m = re.match(r"^chat response (?:names|mentions|lists|states|says|contains|tells)\s+(.+?)(?:\s+\(|\s+as\b|$)", a, re.I)
    if m:
        ns = needles or [m.group(1).strip().strip("`")]
        said = _assistant_text(transcript).lower()
        hits = [n.lower() in said for n in ns]
        return any(hits) if any_of else all(hits)
    if _NEG_RE.search(a):
        if needles:
            scope = _subject_content(subject, files) if subject else _corpus(transcript, files)
            return scope is not None and not any(n in scope for n in needles)
        if tokens:
            return not any(_subject_content(tk, files) is not None for tk in tokens)
        return None
    stripped = re.sub(r"\s+in the working directory$", "", low)
    if stripped.endswith(" exists"):
        target = re.sub(r"\s+in the working directory$", "", a[: len(stripped) - len(" exists")].strip().strip("`"), flags=re.I)
        return _subject_content(target, files) is not None or (target in transcript)
    if subject:
        content = _subject_content(subject, files)
        ns = needles or [tk for tk in tokens if tk != subject]
        if not ns:
            mk = re.match(r"^[\w./-]+\s+(?:references|checks for|has a|has an|includes|declares|defines|mentions|names|flags)\s+(?:the\s+|that\s+|this is a\s+)?[`']?([\w.<>=/-]{2,})", a, re.I)
            if mk:
                return mk.group(1).lower() in content.lower()
            if re.search(r"\b(?:warning|error)\b", low) and re.search(r"\bindicates\b|\bflags\b|\breports\b", low):
                return any(w in content.lower() for w in ("warn", "error", "fail", "problem", "issue"))
            return None
        hits = [n in content for n in ns]
        return any(hits) if any_of else all(hits)
    if needles:
        corpus = _corpus(transcript, files)
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


def inputs_sha256(spec: dict) -> str:
    canon = [{"id": e.get("id"), "prompt": e.get("prompt"), "files": e.get("files")} for e in spec.get("evals", []) if isinstance(e.get("prompt"), str)]
    return hashlib.sha256(json.dumps(canon, sort_keys=True).encode()).hexdigest()


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
    if meta.get("evals_inputs_sha256") and meta["evals_inputs_sha256"] != inputs_sha256(spec):
        stale.append("evals.json prompts/files")
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
            if '"subtype": "error_max_turns"' in transcript or '"subtype":"error_max_turns"' in transcript:
                warns.append(f"{skill_dir.name}/{ev['name']} run{run.get('run')}: TRUNCATED at max-turns — its failures are a runner-cap artifact; re-seed with a higher --max-turns")
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
