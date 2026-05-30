#!/usr/bin/env python3
"""READ-side renderer: typed brief JSON -> resume text for the chat.

Deterministic. Prints the resume prompt + a compact summary + the originating
worktree + branch/repo-mismatch warnings.

CLI: handoff-render.py <key>            (resolve centralized dir)
     handoff-render.py --file <path>    (explicit path)
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("handoff_paths", ROOT / "scripts" / "handoff_paths.py")
_hp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_hp)


def _bullets(label: str, items: list | None) -> str:
    items = items or []
    if not items:
        return ""
    lines = "\n".join(f"  - {x}" for x in items[:5])
    return f"{label}:\n{lines}\n"


def render(obj: dict, current_branch: str | None, current_common_dir: str | None) -> str:
    key = obj.get("key", "?")
    resume = obj.get("resume", {})
    state = obj.get("state", {})
    wt = state.get("worktree", {})
    done_when = resume.get("done_when", "?")
    prompt = resume.get("prompt") or (
        f"read .claude/handoffs/{key}.json and continue. "
        f"next acceptance check: {state.get('next_acceptance_check', '?')}."
    )

    out = []
    rec_common = wt.get("git_common_dir")
    # Normalize both sides (trailing slash, ., relative segments) so a match
    # isn't missed when one side is recorded relative — the WRITE path may
    # store a relative git-common-dir.
    if current_common_dir and rec_common and \
       os.path.normpath(str(current_common_dir)) != os.path.normpath(str(rec_common)):
        out.append(
            f"!! REPO MISMATCH: this brief belongs to a different repo ({rec_common}); not resuming."
        )
    if current_branch and current_branch != state.get("branch"):
        out.append(
            f"!! BRANCH MISMATCH: brief is for '{state.get('branch')}', "
            f"you're on '{current_branch}' — confirm before resuming."
        )

    out.append(f"# Resume — {key}")
    out.append(f"\n## Resume prompt\n> {prompt}")
    out.append(f"\n## Summary")
    out.append(f"- Branch: {state.get('branch', '?')}")
    out.append(
        f"- Written in worktree: {wt.get('root', '?')}"
        + (" (linked)" if wt.get("is_linked") else "")
    )
    out.append(f"- Done when: {done_when}")
    out.append(f"- Next acceptance check: {state.get('next_acceptance_check', '?')}")
    if state.get("diff_summary"):
        out.append(f"- Diff: {state['diff_summary']}")
    body = ""
    body += _bullets("Decisions", state.get("decisions"))
    body += _bullets("Rejected paths", state.get("rejected_paths"))
    body += _bullets("Open risks", state.get("open_risks"))
    if body:
        out.append("\n" + body.rstrip())
    ffr = obj.get("files_read_first") or []
    if ffr:
        out.append("\n## Files to read first")
        for f in ffr:
            out.append(f"- {f.get('path')} — {f.get('why')}")
    return "\n".join(out) + "\n"


def _current(cwd: Path) -> tuple[str | None, str | None]:
    def g(a: list[str]) -> str | None:
        try:
            r = subprocess.run(
                ["git", *a], cwd=cwd, capture_output=True, text=True, timeout=5
            )
            return r.stdout.strip() if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            return None

    return g(["branch", "--show-current"]), g(["rev-parse", "--git-common-dir"])


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "--file":
        path = Path(argv[2])
    elif len(argv) == 2:
        path = _hp.handoffs_dir() / f"{argv[1]}.json"
    else:
        print("usage: handoff-render.py <key> | --file <path>", file=sys.stderr)
        return 2
    if not path.exists():
        print(f"handoff-render: no brief at {path}", file=sys.stderr)
        return 1
    obj = json.loads(path.read_text(encoding="utf-8"))
    cwd = Path.cwd()
    branch, common = _current(cwd)
    if common and not Path(common).is_absolute():
        common = str((cwd / common).resolve())
    print(render(obj, branch, common))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
