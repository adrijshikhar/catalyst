#!/usr/bin/env python3
"""Local eval generator — runs each eval prompt through the `claude` CLI and
writes committed snapshots. NEVER runs in CI (calls a model).

Usage:
    eval-run.py --skill <name> [--runs 3] --now "<iso8601>"

Writes:
    skills/<name>/evals/snapshots/<eval-id>-run<k>.jsonl   (raw transcript)
    skills/<name>/evals/snapshots/results.json             (aggregate + meta)

`--now` is REQUIRED and provided by the shell (no Date.now()-style nondeterminism
inside the script). commit SHA, SKILL.md hash, CLI version, model are stamped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _sh(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT).stdout.strip()


def claude_version() -> str:
    try:
        return _sh(["claude", "--version"]) or "unknown"
    except FileNotFoundError:
        print("ERROR: `claude` CLI not found on PATH — required for eval-run.", file=sys.stderr)
        sys.exit(3)


def run_eval(prompt: str, max_turns: int = 12) -> str:
    """Run one prompt; return the raw stream-json transcript text."""
    proc = subprocess.run(
        ["claude", "-p", prompt, "--output-format", "stream-json",
         "--dangerously-skip-permissions", "--max-turns", str(max_turns), "--verbose"],
        capture_output=True, text=True, cwd=ROOT,
    )
    return proc.stdout


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--now", required=True, help="ISO-8601 timestamp from the shell")
    args = ap.parse_args(argv[1:])

    skill_dir = ROOT / "skills" / args.skill
    evals_json = skill_dir / "evals" / "evals.json"
    if not evals_json.exists():
        print(f"ERROR: {evals_json} not found", file=sys.stderr)
        return 2
    spec = json.loads(evals_json.read_text())
    snap_dir = skill_dir / "evals" / "snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)

    version = claude_version()
    commit = _sh(["git", "rev-parse", "HEAD"]) or "unknown"
    md = skill_dir / "SKILL.md"
    md_hash = hashlib.sha256(md.read_bytes()).hexdigest() if md.exists() else ""

    aggregate = {
        "meta": {
            "generated_at": args.now,
            "commit_sha": commit,
            "skill_md_sha256": md_hash,
            "claude_cli_version": version,
            "model": "default",
            "n_evals": len(spec.get("evals", [])),
        },
        "evals": {},
    }
    for ev in spec.get("evals", []):
        runs = []
        for k in range(args.runs):
            transcript = run_eval(ev["prompt"])
            raw_path = snap_dir / f"{ev['id']}-run{k}.jsonl"
            raw_path.write_text(transcript, encoding="utf-8")
            runs.append({"run": k, "transcript_text": transcript})
        aggregate["evals"][str(ev["id"])] = {"name": ev["name"], "runs": runs}
        print(f"ran {args.skill}/{ev['name']} x{args.runs}")
    (snap_dir / "results.json").write_text(json.dumps(aggregate, indent=2), encoding="utf-8")
    print(f"wrote {snap_dir / 'results.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
