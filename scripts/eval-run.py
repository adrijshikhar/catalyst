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

# Snapshots are committed, so transcripts must not leak the developer's absolute
# home path (CI's no-personal-paths lint rejects '/Users/<name>' etc.). Replace
# the home dir with a stable, portable placeholder before writing.
_HOME = str(Path.home())


def _scrub(text: str) -> str:
    """Strip the developer's home path from a transcript before it is committed."""
    return text.replace(_HOME, "$HOME") if _HOME and _HOME != "/" else text


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
    # `claude -p` can exit non-zero purely because an UNRELATED lifecycle hook
    # failed (e.g. a global SessionEnd hook erroring with "Hook cancelled"),
    # even though the run itself produced a complete transcript. A stream-json
    # `{"type":"result"}` object marks a finished run — if it's present the
    # transcript is usable, so warn and keep it rather than aborting the whole
    # seed. Only hard-fail when no result was produced.
    produced_result = '"type":"result"' in proc.stdout
    if proc.returncode != 0:
        # Keep the transcript only if it finished AND is not a login-wall result
        # (which also carries a `result` object). The auth wall must still hard-
        # fail on every run, not just the first.
        if produced_result and not looks_unauthenticated(proc.stdout):
            print(
                f"WARN: `claude -p` exited {proc.returncode} but produced a result "
                f"transcript (likely an unrelated lifecycle-hook failure); using it. "
                f"stderr head: {proc.stderr.strip()[:160]}",
                file=sys.stderr,
            )
            return proc.stdout
        print(
            f"ERROR: `claude -p` exited {proc.returncode} with no result transcript. "
            f"stderr:\n{proc.stderr.strip()}",
            file=sys.stderr,
        )
        sys.exit(5)
    return proc.stdout


def looks_unauthenticated(transcript: str) -> bool:
    """Detect the headless auth wall: `claude -p` returns a 'Please run /login'
    notice with zero token usage instead of doing the work. Seeding against this
    silently produces garbage snapshots (observed 2026-05-29)."""
    login_wall = "Please run /login" in transcript
    zero_usage = '"total_cost_usd":0' in transcript and '"output_tokens":0' in transcript
    return login_wall and zero_usage


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
    first_run = True
    for ev in spec.get("evals", []):
        # Deferred evals carry a null/absent prompt — intentional placeholders
        # that are not run yet. Skip them rather than passing None to subprocess
        # (which crashes with "expected str ... not NoneType"). The grader skips
        # them by the same rule, so no snapshot is expected for them.
        if not isinstance(ev.get("prompt"), str):
            print(f"skip {args.skill}/{ev.get('name', ev.get('id'))} (deferred — no prompt)")
            continue
        runs = []
        for k in range(args.runs):
            transcript = run_eval(ev["prompt"])
            # Auth-wall guard: after the very first run, abort before spending
            # the rest if the child `claude` is unauthenticated — otherwise we
            # snapshot dozens of garbage login-wall transcripts.
            if first_run:
                first_run = False
                if looks_unauthenticated(transcript):
                    print(
                        "ERROR: child `claude` CLI is not authenticated "
                        "(hit the 'Please run /login' wall, zero token usage). "
                        "Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in the "
                        "environment eval-run.py runs in, then retry.",
                        file=sys.stderr,
                    )
                    return 4
            transcript = _scrub(transcript)
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
