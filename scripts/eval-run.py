#!/usr/bin/env python3
"""Local eval generator — Lane B. Runs each eval prompt through the `claude` CLI
in an isolated, fixture-staged workspace and writes committed snapshots.
NEVER runs in CI (calls a model).

Usage:
    eval-run.py --skill <name> --model <sonnet|haiku|opus|...> --now "<iso8601>"
                [--runs 3] [--only 0,3,13] [--max-turns 12]

Per run:
  * a fresh temp workspace; the eval's `files[]` fixtures are materialized;
    `.git-HEAD` (if present) becomes a real git branch; fixture trees the prompt
    names under skills/<skill>/evals/fixtures/ are copied in at the same relative
    path; `scripts/` is symlinked to this checkout so prompts that call
    `python3 scripts/handoff-*.py` resolve.
  * `claude -p` runs with cwd = workspace and `--plugin-dir <this checkout>`, so
    the SKILL.md under test is the working tree, not the installed cache.
  * the transcript (scrubbed of $HOME) and every file the run wrote are captured.

Writes:
    skills/<name>/evals/snapshots/<id>-run<k>.jsonl        raw transcript
    skills/<name>/evals/snapshots/results.json             aggregate + meta + captured files

`--now` is REQUIRED (shell-provided; no clock inside). Model, commit SHA, SKILL.md
and evals.json hashes, CLI version are stamped so the grader can prove freshness.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_HOME = str(Path.home())
_FIXTURE_RE = re.compile(r"skills/[\w-]+/evals/fixtures/[\w.-]+")
_CAPTURE_MAX = 64 * 1024
_SKIP_DIRS = {".git", "scripts", "node_modules", "__pycache__"}


def _scrub(text: str) -> str:
    return text.replace(_HOME, "$HOME") if _HOME and _HOME != "/" else text


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ""


def _sh(cmd: list[str], cwd: Path = ROOT) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd).stdout.strip()


def claude_version() -> str:
    try:
        return _sh(["claude", "--version"]) or "unknown"
    except FileNotFoundError:
        print("ERROR: `claude` CLI not found on PATH", file=sys.stderr)
        sys.exit(3)


def materialize(ev: dict, skill: str, ws: Path) -> None:
    """Stage one eval's inputs into an empty workspace."""
    files = ev.get("files") or []
    items = files.items() if isinstance(files, dict) else [(f["path"], f.get("content", "")) for f in files]
    branch = None
    for rel, content in items:
        if isinstance(content, dict):
            content = content.get("content", "")
        target = ws / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        if rel == ".git-HEAD":
            branch = content.strip() or None
    for rel in sorted(set(_FIXTURE_RE.findall(ev.get("prompt", "")))):
        src = ROOT / rel
        if src.is_dir():
            shutil.copytree(src, ws / rel, dirs_exist_ok=True)
    # Prompts and SKILL.md call `python3 scripts/handoff-*.py`; point at this checkout.
    if not (ws / "scripts").exists():
        os.symlink(ROOT / "scripts", ws / "scripts")
    if branch or (ws / ".claude").exists() or (ws / ".catalyst").exists():
        subprocess.run(["git", "init", "-q"], cwd=ws, check=True)
        env = {**os.environ, "GIT_AUTHOR_NAME": "eval", "GIT_AUTHOR_EMAIL": "eval@catalyst", "GIT_COMMITTER_NAME": "eval", "GIT_COMMITTER_EMAIL": "eval@catalyst"}
        subprocess.run(["git", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "fixture"], cwd=ws, env=env, check=True)
        if branch:
            subprocess.run(["git", "checkout", "-q", "-B", branch], cwd=ws, check=True)


def capture(ws: Path) -> dict[str, str]:
    """Every regular file the run left behind (text, capped), keyed by relative path."""
    out: dict[str, str] = {}
    for p in sorted(ws.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(ws)
        if any(part in _SKIP_DIRS for part in rel.parts):
            continue
        try:
            text = p.read_bytes()[:_CAPTURE_MAX].decode("utf-8", errors="replace")
        except OSError:
            continue
        out[str(rel)] = _scrub(text)
    return out


def looks_unauthenticated(transcript: str) -> bool:
    return "Please run /login" in transcript and '"total_cost_usd":0' in transcript and '"output_tokens":0' in transcript


def run_eval(prompt: str, ws: Path, model: str, max_turns: int) -> str:
    proc = subprocess.run(
        ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json",
         "--dangerously-skip-permissions", "--max-turns", str(max_turns), "--verbose",
         "--plugin-dir", str(ROOT)],
        capture_output=True, text=True, cwd=ws,
    )
    produced = '"type":"result"' in proc.stdout
    if proc.returncode != 0 and not (produced and not looks_unauthenticated(proc.stdout)):
        print(f"ERROR: `claude -p` exited {proc.returncode} with no result transcript. stderr:\n{proc.stderr.strip()[:400]}", file=sys.stderr)
        sys.exit(5)
    return proc.stdout


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--now", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--only", default="", help="comma-separated eval ids")
    ap.add_argument("--max-turns", type=int, default=12)
    ap.add_argument("--out", default="", help="snapshot dir override (default skills/<skill>/evals/snapshots)")
    args = ap.parse_args(argv[1:])

    skill_dir = ROOT / "skills" / args.skill
    evals_json = skill_dir / "evals" / "evals.json"
    if not evals_json.exists():
        print(f"ERROR: {evals_json} not found", file=sys.stderr)
        return 2
    spec = json.loads(evals_json.read_text())
    snap_dir = Path(args.out) if args.out else skill_dir / "evals" / "snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    aggregate = {
        "meta": {
            "generated_at": args.now,
            "commit_sha": _sh(["git", "rev-parse", "HEAD"]) or "unknown",
            "skill_md_sha256": _sha(skill_dir / "SKILL.md"),
            "evals_json_sha256": _sha(evals_json),
            "claude_cli_version": claude_version(),
            "model": args.model,
            "runs_per_eval": args.runs,
            "n_evals": 0,
        },
        "evals": {},
    }
    first = True
    for ev in spec.get("evals", []):
        eid = str(ev.get("id"))
        if only and eid not in only:
            continue
        if not isinstance(ev.get("prompt"), str):
            print(f"skip {args.skill}/{ev.get('name', eid)} (deferred — no prompt)")
            continue
        runs = []
        for k in range(args.runs):
            with tempfile.TemporaryDirectory(prefix=f"catalyst-eval-{eid}-") as d:
                ws = Path(d)
                materialize(ev, args.skill, ws)
                transcript = run_eval(ev["prompt"], ws, args.model, args.max_turns)
                if first:
                    first = False
                    if looks_unauthenticated(transcript):
                        print("ERROR: child `claude` is not authenticated (login wall).", file=sys.stderr)
                        return 4
                transcript = _scrub(transcript)
                files = capture(ws)
            (snap_dir / f"{eid}-run{k}.jsonl").write_text(transcript, encoding="utf-8")
            runs.append({"run": k, "transcript_file": f"{eid}-run{k}.jsonl", "files": files})
            print(f"  {args.skill}/{ev['name']} run{k}: {len(files)} files captured, {len(transcript)//1024} KB transcript")
        aggregate["evals"][eid] = {"name": ev["name"], "category": ev.get("category", "capability"), "runs": runs}
        aggregate["meta"]["n_evals"] += 1
    (snap_dir / "results.json").write_text(json.dumps(aggregate, indent=1), encoding="utf-8")
    print(f"wrote {snap_dir / 'results.json'} ({aggregate['meta']['n_evals']} evals x {args.runs} runs, model={args.model})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
