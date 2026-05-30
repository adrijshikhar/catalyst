#!/usr/bin/env python3
"""READ-side renderer: typed brief JSON -> resume text for the chat.

Deterministic. Prints the resume prompt + a compact summary + the originating
worktree + branch/repo-mismatch warnings.

CLI: handoff-render.py <key>                    (resolve centralized dir)
     handoff-render.py --file <path>            (explicit path)
     handoff-render.py --reground <key>         (compact read-only re-grounding)
     handoff-render.py --reground --file <path>
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


def _git_root(p: str) -> str:
    """Normalize a git dir to its SHARED common dir for repo comparison.

    A linked worktree's private git dir is `<common>/.git/worktrees/<name>`;
    the shared common dir is `<common>/.git`. Collapse the `/worktrees/<name>`
    suffix so a brief that recorded either form still matches the resuming
    session's `git rev-parse --git-common-dir`. Defense-in-depth: WRITE is
    instructed to store the shared common dir, but tolerate the worktree form.
    """
    norm = os.path.normpath(str(p))
    marker = os.sep + "worktrees" + os.sep
    idx = norm.find(marker)
    return norm[:idx] if idx != -1 else norm


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
        f"resume handoff '{key}': run `/catalyst:handoff resume` (READ mode), then continue. "
        f"next acceptance check: {state.get('next_acceptance_check', '?')}."
    )

    out = []
    rec_common = wt.get("git_common_dir")
    # The WRITE path may store a relative git-common-dir (`git rev-parse
    # --git-common-dir` returns ".git" in a MAIN checkout). The current side is
    # already absolute (resolved in main()), so resolve a relative stored value
    # against the recorded worktree root before comparing — otherwise a brief
    # written AND resumed in the same main checkout would falsely mismatch.
    if rec_common and not Path(rec_common).is_absolute():
        rec_common = os.path.join(wt.get("root", ""), rec_common)
    if current_common_dir and rec_common and \
       _git_root(current_common_dir) != _git_root(rec_common):
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


def render_reground(obj: dict) -> str:
    """Compact, read-only mid-session re-grounding brief.

    Emits ONLY the load-bearing fields needed to counter lost-in-the-middle
    recall degradation: goal (done_when + next_acceptance_check), locked
    decisions, and files to keep in view.  No summary scaffold, no worktree
    lines, no branch/repo-mismatch blocks.
    """
    resume = obj.get("resume", {})
    state = obj.get("state", {})
    key = obj.get("key", "session")

    out: list[str] = [f"# Reground — {key}"]

    # Goal block
    goal_lines: list[str] = []
    done_when = resume.get("done_when")
    if done_when:
        goal_lines.append(f"  - Done when: {done_when}")
    nac = state.get("next_acceptance_check")
    if nac:
        goal_lines.append(f"  - Next acceptance check: {nac}")
    if goal_lines:
        out.append("\n## Goal")
        out.extend(goal_lines)

    # Locked decisions
    decisions_block = _bullets("Locked decisions", state.get("decisions"))
    if decisions_block:
        out.append("\n## Locked decisions")
        out.append(decisions_block.rstrip())

    # Files to keep in view
    ffr = obj.get("files_read_first") or []
    if ffr:
        out.append("\n## Files to keep in view")
        for f in ffr:
            out.append(f"  - {f.get('path')} — {f.get('why')}")

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


def _key_path(key: str) -> Path | None:
    """Resolve <key> to <store>/<key>.json, refusing keys that escape the store.

    The key is branch/user-derived; a value like '../../etc/passwd' would
    otherwise let the renderer read arbitrary files. The --file override is the
    sanctioned escape hatch for explicit paths — this guard is key-only.
    """
    store = _hp.handoffs_dir().resolve()
    path = (store / f"{key}.json").resolve()
    try:
        path.relative_to(store)
    except ValueError:
        return None
    return path


def main(argv: list[str]) -> int:
    # Detect --reground flag; it may appear as the first or second argument.
    if "--reground" in argv[1:]:
        reground = True
        rest = [a for a in argv[1:] if a != "--reground"]
    else:
        reground = False
        rest = argv[1:]

    if len(rest) >= 2 and rest[0] == "--file":
        path: Path | None = Path(rest[1])
    elif len(rest) == 1:
        path = _key_path(rest[0])
        if path is None:
            print(f"handoff-render: key '{rest[0]}' escapes the handoffs store", file=sys.stderr)
            return 1
    else:
        print("usage: handoff-render.py [--reground] <key> | --file <path>", file=sys.stderr)
        return 2

    if path is None or not path.exists():
        print(f"handoff-render: no brief at {path}", file=sys.stderr)
        return 1
    obj = json.loads(path.read_text(encoding="utf-8"))
    if reground:
        print(render_reground(obj))
        return 0
    cwd = Path.cwd()
    branch, common = _current(cwd)
    if common and not Path(common).is_absolute():
        common = str((cwd / common).resolve())
    print(render(obj, branch, common))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
