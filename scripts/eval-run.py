#!/usr/bin/env python3
"""Local eval generator — Lane B. Runs each eval prompt through the `claude` CLI
in an isolated, fixture-staged workspace and writes committed snapshots.
NEVER runs in CI (calls a model).

Usage:
    eval-run.py --skill <name> --model <sonnet|haiku|opus|...> --now "<iso8601>"
                [--host claude|antigravity] [--runs 3] [--only 0,3,13] [--max-turns 30]

Hosts:
  * claude (default): `claude -p … --setting-sources project --plugin-dir <checkout>`;
    snapshots land in skills/<name>/evals/snapshots/ and are the CI-enforced lane.
  * antigravity: `agy -p … --add-dir <workspace>`; the checkout's skills are staged
    as <workspace>/.agents/skills/<skill> symlinks (Antigravity's workspace-level
    discovery), the agy event stream is normalised to the Claude stream-json shape
    the grader reads, and snapshots land in skills/<name>/evals/snapshots-antigravity/.

Per run:
  * a fresh temp workspace; the eval's `files[]` fixtures are materialized;
    `.git-HEAD` (if present) becomes a real git branch; fixture trees the prompt
    names under skills/<skill>/evals/fixtures/ are copied in at the same relative
    path; `scripts/` is symlinked to this checkout so prompts that call
    `python3 scripts/handoff-*.py` resolve.
  * `claude -p` runs with cwd = workspace, `--setting-sources project` (no user
    settings, no user-installed plugins) and `--plugin-dir <this checkout>`, so
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
_SKIP_DIRS = {".git", "scripts", "node_modules", "__pycache__", ".agents"}


def _scrub(text: str) -> str:
    return text.replace(_HOME, "$HOME") if _HOME and _HOME != "/" else text


def _condense(transcript: str) -> str:
    """Keep what the grader reads: assistant turns (text + tool_use), user turns
    (tool results — renderer output lives there) and the final result. Drops the
    system init and stream bookkeeping."""
    keep = []
    for line in transcript.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") in ("assistant", "user", "result"):
            keep.append(line)
    return "\n".join(keep) + "\n"


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ""


def inputs_sha256(spec: dict) -> str:
    """Hash of what the model SAW (id, prompt, files) — assertions are grading-side and
    may be tightened without re-running; a changed prompt or fixture must re-seed."""
    canon = [{"id": e.get("id"), "prompt": e.get("prompt"), "files": e.get("files")} for e in spec.get("evals", []) if isinstance(e.get("prompt"), str)]
    return hashlib.sha256(json.dumps(canon, sort_keys=True).encode()).hexdigest()


def _sh(cmd: list[str], cwd: Path = ROOT) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd).stdout.strip()




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


_INFRA_MARKERS = ("hit your session limit", "hit your usage limit", "usage limit reached", "rate limit")


def infra_failure(transcript: str) -> str | None:
    """A run that never reached the model is an infrastructure failure, not a skill
    result: seeding must stop so an empty transcript is never graded as a miss."""
    if looks_unauthenticated(transcript):
        return "child `claude` is not authenticated (login wall)"
    if '"num_turns": 1' in transcript or '"num_turns":1' in transcript:
        low = transcript.lower()
        for m in _INFRA_MARKERS:
            if m in low:
                return f"child CLI reported '{m}' before doing any work"
        if '"host": "antigravity"' in transcript and '"is_error": true' in transcript:
            return "child `agy` returned an error result before doing any work"
    return None


# ---------------------------------------------------------------- hosts

# Only tools that actually RUN a subagent count as dispatch. define_subagent and
# manage_subagents are setup/bookkeeping: on 2026-09-08 three Flash runs defined a
# subagent, never invoked it, did the task themselves and narrated a "subagent report".
_SUBAGENT_TOOLS = {"invoke_subagent", "browser_subagent"}


def stage_antigravity_skills(ws: Path) -> None:
    """Antigravity discovers `.agents/skills/<name>` from the cwd upward; a symlink per
    checkout skill puts the working tree under test without touching the user's
    global plugin install."""
    dst = ws / ".agents" / "skills"
    dst.mkdir(parents=True, exist_ok=True)
    for sk in sorted((ROOT / "skills").iterdir()):
        if (sk / "SKILL.md").exists() and not (dst / sk.name).exists():
            os.symlink(sk, dst / sk.name)


def normalize_antigravity(raw: str) -> str:
    """agy --output-format stream-json emits {event: init|step_update|result}. Rewrite it
    into the Claude stream-json lines the grader understands: assistant text and
    tool_use, user tool_result, and a final result. Subagent tools are named
    `Agent` so dispatch-count assertions read across hosts; the original name is
    kept as `host_tool`."""
    out: list[str] = []
    text_by_step: dict[int, list[str]] = {}
    tool_steps = 0
    status = None
    response = ""
    for line in raw.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        kind = ev.get("event")
        body = ev.get(kind) or {}
        if kind == "step_update":
            st = body.get("step_type")
            if st == "agent_response":
                idx = body.get("step_index", 0)
                if body.get("text_delta"):
                    text_by_step.setdefault(idx, []).append(body["text_delta"])
                if body.get("state") == "DONE" and text_by_step.get(idx):
                    out.append(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "".join(text_by_step.pop(idx))}]}}))
            elif st == "subagent":
                # agy reports subagent dispatch as its own step type (tool_name
                # invoke_subagent, details in subagent_info), not as a `tool` step.
                info = body.get("subagent_info") or {}
                if body.get("state") == "ACTIVE":
                    tool_steps += 1
                    out.append(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Agent",
                               "host_tool": body.get("tool_name") or "invoke_subagent", "input": info}]}}))
                elif body.get("state") == "DONE":
                    out.append(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "content": json.dumps(info)[:4000]}]}}))
            elif st == "tool":
                info = body.get("tool_info") or {}
                name = body.get("tool_name") or info.get("name") or "tool"
                if body.get("state") == "ACTIVE":
                    tool_steps += 1
                    block = {"type": "tool_use", "name": "Agent" if name in _SUBAGENT_TOOLS else name,
                             "host_tool": name, "input": info.get("parameters") or {}}
                    out.append(json.dumps({"type": "assistant", "message": {"content": [block]}}))
                elif body.get("state") == "DONE" and info.get("output") is not None:
                    out.append(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "content": str(info.get("output"))}]}}))
        elif kind == "result":
            status = body.get("status")
            response = body.get("response") or ""
    for idx in sorted(text_by_step):
        out.append(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "".join(text_by_step[idx])}]}}))
    out.append(json.dumps({"type": "result", "subtype": "success" if status == "SUCCESS" else "error",
                           "is_error": status != "SUCCESS", "num_turns": tool_steps + 1, "host": "antigravity",
                           "host_status": status, "result": response}))
    return "\n".join(out) + "\n"


def host_version(host: str) -> str:
    exe = {"claude": "claude", "antigravity": "agy"}[host]
    try:
        return _sh([exe, "--version"]) or "unknown"
    except FileNotFoundError:
        print(f"ERROR: `{exe}` CLI not found on PATH", file=sys.stderr)
        sys.exit(3)


def build_command(host: str, prompt: str, ws: Path, model: str, max_turns: int) -> list[str]:
    if host == "claude":
        return ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json",
                "--dangerously-skip-permissions", "--max-turns", str(max_turns), "--verbose",
                "--setting-sources", "project", "--plugin-dir", str(ROOT)]
    if host == "antigravity":
        # no --max-turns equivalent; the print timeout bounds a runaway run instead
        return ["agy", "-p", prompt, "--model", model, "--output-format", "stream-json",
                "--dangerously-skip-permissions", "--add-dir", str(ws), "--print-timeout", "10m"]
    raise SystemExit(f"unknown host {host}")


def run_eval(prompt: str, ws: Path, model: str, max_turns: int, host: str = "claude") -> str:
    proc = subprocess.run(build_command(host, prompt, ws, model, max_turns), capture_output=True, text=True, cwd=ws)
    raw = proc.stdout if host == "claude" else normalize_antigravity(proc.stdout)
    produced = '"type":"result"' in raw or '"type": "result"' in raw
    if proc.returncode != 0 and not (produced and not looks_unauthenticated(raw)):
        print(f"ERROR: {host} CLI exited {proc.returncode} with no result transcript. stderr:\n{proc.stderr.strip()[:400]}", file=sys.stderr)
        sys.exit(5)
    return raw


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--host", choices=("claude", "antigravity"), default="claude")
    ap.add_argument("--now", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--only", default="", help="comma-separated eval ids")
    ap.add_argument("--max-turns", type=int, default=30, help="WRITE/RECOVER flows take ~14 tool calls; 12 truncated 8/54 seed runs on 2026-09-06")
    ap.add_argument("--out", default="", help="snapshot dir override (default skills/<skill>/evals/snapshots)")
    args = ap.parse_args(argv[1:])

    skill_dir = ROOT / "skills" / args.skill
    evals_json = skill_dir / "evals" / "evals.json"
    if not evals_json.exists():
        print(f"ERROR: {evals_json} not found", file=sys.stderr)
        return 2
    spec = json.loads(evals_json.read_text())
    default_snap = "snapshots" if args.host == "claude" else f"snapshots-{args.host}"
    snap_dir = Path(args.out) if args.out else skill_dir / "evals" / default_snap
    snap_dir.mkdir(parents=True, exist_ok=True)
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    aggregate = {
        "meta": {
            "generated_at": args.now,
            "commit_sha": _sh(["git", "rev-parse", "HEAD"]) or "unknown",
            "skill_md_sha256": _sha(skill_dir / "SKILL.md"),
            "evals_inputs_sha256": inputs_sha256(spec),
            "host": args.host,
            "claude_cli_version": host_version("claude") if args.host == "claude" else None,
            "host_cli_version": host_version(args.host),
            "model": args.model,
            "runs_per_eval": args.runs,
            "max_turns": args.max_turns,
            "n_evals": 0,
        },
        "evals": {},
    }
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
                if args.host == "antigravity":
                    stage_antigravity_skills(ws)
                transcript = run_eval(ev["prompt"], ws, args.model, args.max_turns, args.host)
                why = infra_failure(transcript)
                if why:
                    print(f"ERROR: {why}. Stopping at {args.skill}/{ev['name']} run{k}; "
                          f"{aggregate['meta']['n_evals']} completed evals were NOT written to results.json — "
                          f"re-run with --only for the rest and merge.", file=sys.stderr)
                    return 4
                transcript = _scrub(_condense(transcript))
                files = capture(ws)
            (snap_dir / f"{eid}-run{k}.jsonl").write_text(transcript, encoding="utf-8")
            runs.append({"run": k, "transcript_file": f"{eid}-run{k}.jsonl", "files": files})
            print(f"  {args.skill}/{ev['name']} run{k}: {len(files)} files captured, {len(transcript)//1024} KB transcript")
        aggregate["evals"][eid] = {"name": ev["name"], "category": ev.get("category", "capability"), "runs": runs}
        aggregate["meta"]["n_evals"] += 1
    (snap_dir / "results.json").write_text(json.dumps(aggregate, indent=1), encoding="utf-8")
    print(f"wrote {snap_dir / 'results.json'} ({aggregate['meta']['n_evals']} evals x {args.runs} runs, host={args.host}, model={args.model})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
