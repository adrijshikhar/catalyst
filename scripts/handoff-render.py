#!/usr/bin/env python3
"""READ-side renderer: typed brief JSON -> resume text for the chat.

Deterministic. Prints the resume prompt + a compact summary + the originating
worktree + branch/repo-mismatch warnings.

CLI: handoff-render.py <key>                    (resolve centralized dir)
     handoff-render.py --file <path>            (explicit path)
     handoff-render.py --reground <key>         (compact read-only re-grounding)
     handoff-render.py --reground --file <path>
     handoff-render.py --brief <path>           (BRIEF-mode render, capped)
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("handoff_paths", ROOT / "scripts" / "handoff_paths.py")
_hp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_hp)

_cspec = importlib.util.spec_from_file_location(
    "catalyst_config", ROOT / "scripts" / "catalyst_config.py")
_cc = importlib.util.module_from_spec(_cspec)
_cspec.loader.exec_module(_cc)


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


def _missing_files(obj: dict) -> list[str]:
    """Return files_read_first paths that no longer exist.

    Absolute paths are checked as-is — briefs legitimately point outside the
    worktree (e.g. at a sibling docs repo). Relative paths resolve against the
    recorded worktree root, NEVER cwd: a brief resumed from a linked worktree
    must resolve against the tree it was written in.
    """
    wt_root = ((obj.get("state") or {}).get("worktree") or {}).get("root", "")
    missing: list[str] = []
    for f in obj.get("files_read_first") or []:
        p = f.get("path", "")
        if not p:
            continue
        cand = Path(p)
        if not cand.is_absolute():
            cand = Path(wt_root) / cand
        try:
            exists = cand.exists()
        except OSError:
            exists = True  # fail open — don't warn on an un-stattable path
        if not exists:
            missing.append(p)
    return missing


def _stale_hours() -> float:
    """Staleness threshold: CATALYST_HANDOFF_STALE_HOURS > catalyst.json > 24."""
    try:
        return float(_cc.get("handoff.stale_hours", 24))
    except (TypeError, ValueError):
        return 24.0


def _stale_note(timestamp: str, now: datetime) -> str | None:
    """Return a STALE warning if the brief is older than the threshold, else None."""
    try:
        ts = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return None  # fail open — unparseable timestamp: no age signal
    hours = (now - ts).total_seconds() / 3600.0
    if hours < _stale_hours():
        return None
    agestr = f"{int(round(hours))}h" if hours < 48 else f"{int(hours // 24)}d"
    return (f"!! STALE: brief written ~{agestr} ago ({timestamp}) — "
            f"diff current git state before resuming.")


def render(obj: dict, current_branch: str | None = None,
           current_common_dir: str | None = None, now: datetime | None = None,
           commits_since: int | None = None, sha_in_history: bool = True) -> str:
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

    if now is not None:
        stale = _stale_note(obj.get("timestamp", ""), now)
        if stale:
            out.append(stale)

    for mp in _missing_files(obj):
        out.append(
            f"!! MISSING: {mp} — referenced file no longer exists; verify before resuming."
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
    if commits_since is not None:
        out.append(f"- Commits since brief written: {commits_since}")
    elif (state.get("head_sha")) and not sha_in_history:
        out.append(
            f"- Brief HEAD {state['head_sha'][:7]} not in current history — tree diverged since WRITE."
        )
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


def render_brief(obj: dict) -> str:
    """BRIEF-mode render: minimum viable context for a subagent.

    Per the SKILL's BRIEF rules this omits the identity/storage fields —
    `key`, `schema_version`, the on-disk brief path — since nothing persists.
    It keeps `files_read_first` path pointers (the consumer needs them), and
    the `resume` block becomes `## Task` — named for the subagent's
    perspective, not the session's.
    """
    resume = obj.get("resume", {})
    state = obj.get("state", {})
    out = ["## Task",
           f"- Done when: {resume.get('done_when', '?')}",
           f"- Acceptance check: {state.get('next_acceptance_check', '?')}"]
    if resume.get("resume_by"):
        out.append(f"- Start by: {resume['resume_by']}")
    if obj.get("scope"):
        out.append(f"\n## Scope\n{obj['scope']}")
    for label, items in (("Locked decisions", state.get("decisions")),
                         ("Do not retry", state.get("rejected_paths")),
                         ("Open risks", state.get("open_risks"))):
        if items:
            out.append(f"\n## {label}")
            out.extend(f"- {x}" for x in items)
    ffr = obj.get("files_read_first") or []
    if ffr:
        out.append("\n## Read first")
        out.extend(f"- {f.get('path')} — {f.get('why')}" for f in ffr)
    if obj.get("return_instructions"):
        out.append(f"\n## Return\n{obj['return_instructions']}")
    return "\n".join(out) + "\n"


def _brief_section_counts(lines: list[str]) -> list[tuple[str, int]]:
    counts: list[tuple[str, int]] = []
    section, n = "(preamble)", 0
    for line in lines:
        if line.startswith("## "):
            if n:
                counts.append((section, n))
            section, n = line[3:], 1
        else:
            n += 1
    if n:
        counts.append((section, n))
    return counts


def _current(cwd: Path) -> tuple[str | None, str | None, str | None]:
    def g(a: list[str]) -> str | None:
        try:
            r = subprocess.run(
                ["git", *a], cwd=cwd, capture_output=True, text=True, timeout=5
            )
            return r.stdout.strip() if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            return None

    return (g(["branch", "--show-current"]),
            g(["rev-parse", "--git-common-dir"]),
            g(["rev-parse", "HEAD"]))


def _commits_since(cwd: Path, brief_sha: str) -> tuple[int | None, bool]:
    """(count, in_history). count None when unknown; in_history False only when
    the brief sha is definitively NOT an ancestor of HEAD."""
    try:
        anc = subprocess.run(["git", "merge-base", "--is-ancestor", brief_sha, "HEAD"],
                             cwd=cwd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None, True
    if anc.returncode == 1:
        return None, False          # sha not in current history — diverged
    if anc.returncode != 0:
        return None, True           # unknown sha / git error — say nothing
    try:
        cnt = subprocess.run(["git", "rev-list", "--count", f"{brief_sha}..HEAD"],
                             cwd=cwd, capture_output=True, text=True, timeout=5)
        return (int(cnt.stdout.strip()), True) if cnt.returncode == 0 else (None, True)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None, True


def _key_path(key: str) -> Path | None:
    """Resolve <key> to <store>/<key>.json, refusing keys that escape the store.

    The key is branch/user-derived; a value like '../../etc/passwd' would
    otherwise let the renderer read arbitrary files. The --file override is the
    sanctioned escape hatch for explicit paths — this guard is key-only.
    """
    store = _hp.handoffs_dir().resolve()
    cand = Path(key)
    # Tolerate three caller forms without double-appending ".json":
    #   bare slug "feat-x"            -> <store>/feat-x.json
    #   filename  "feat-x.json"       -> <store>/feat-x.json
    #   full path "<store>/feat-x.json" (absolute or with dirs) -> itself
    # A bare slug (single component, no .json) is the common path; anything
    # that already looks like a path/file is resolved as-is. The containment
    # check below still rejects keys/paths that escape the store.
    if cand.is_absolute() or len(cand.parts) > 1 or cand.suffix == ".json":
        base = cand if cand.is_absolute() else (store / cand)
        path = base.resolve()
    else:
        path = (store / f"{key}.json").resolve()
    try:
        path.relative_to(store)
    except ValueError:
        return None
    return _hp.read_path(path, store)


def main(argv: list[str]) -> int:
    # Detect --reground flag; it may appear as the first or second argument.
    if "--reground" in argv[1:]:
        reground = True
        rest = [a for a in argv[1:] if a != "--reground"]
    else:
        reground = False
        rest = argv[1:]

    if "--brief" in argv[1:]:
        brief = True
        rest = [a for a in rest if a != "--brief"]
    else:
        brief = False

    now = datetime.now(timezone.utc)
    if "--now" in rest:
        i = rest.index("--now")
        try:
            now = datetime.strptime(rest[i + 1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except (IndexError, ValueError):
            pass
        del rest[i:i + 2]

    if len(rest) >= 2 and rest[0] == "--file":
        path: Path | None = Path(rest[1])
    elif brief and len(rest) == 1:
        # BRIEF mode's argument is always an explicit path (often an ad hoc
        # temp file assembled for a subagent dispatch, per the SKILL's BRIEF
        # verification step) — never a store key, so it bypasses _key_path's
        # store-containment check the way --file does.
        path = Path(rest[0])
    elif len(rest) == 1:
        path = _key_path(rest[0])
        if path is None:
            print(f"handoff-render: key '{rest[0]}' escapes the handoffs store", file=sys.stderr)
            return 1
    else:
        print("usage: handoff-render.py [--reground] <key> | --file <path> | --brief <path>", file=sys.stderr)
        return 2

    if path is None or not path.exists():
        print(f"handoff-render: no brief at {path}", file=sys.stderr)
        return 1
    obj = json.loads(path.read_text(encoding="utf-8"))
    if brief:
        text = render_brief(obj)
        try:
            cap = int(_cc.get("handoff.brief_max_lines", 30))
        except (TypeError, ValueError):
            cap = 30
        print(text, end="")
        lines = text.rstrip("\n").split("\n")
        if len(lines) > cap:
            print(f"handoff-render: BRIEF over cap — {len(lines)} lines > {cap}. "
                  "Re-decompose the subtask or trim these sections:", file=sys.stderr)
            for sec, cnt in _brief_section_counts(lines):
                print(f"  {sec}: {cnt} lines", file=sys.stderr)
            return 1
        return 0
    if reground:
        print(render_reground(obj))
        return 0
    cwd = Path.cwd()
    branch, common, head = _current(cwd)
    if common and not Path(common).is_absolute():
        common = str((cwd / common).resolve())
    commits_since, sha_in_history = None, True
    brief_sha = (obj.get("state") or {}).get("head_sha")
    if brief_sha and head:
        commits_since, sha_in_history = _commits_since(cwd, brief_sha)
    print(render(obj, branch, common, now=now,
                 commits_since=commits_since, sha_in_history=sha_in_history))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
