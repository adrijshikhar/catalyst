#!/usr/bin/env python3
"""Resolve the centralized handoffs directory + load the brief schema.

The handoffs dir is repo-wide: anchored at the MAIN worktree (parent of the
shared git-common-dir), so every linked worktree shares one store keyed by
branch. Mirrors scripts/handoff-dir.sh (bash) — kept in sync by
tests/test_handoff_paths.py.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "skills" / "handoff" / "brief.schema.json"
_spec = importlib.util.spec_from_file_location("catalyst_config", ROOT / "scripts/catalyst_config.py")
_cc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cc)


def _git(args: list[str], cwd: Path) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def handoffs_dir(cwd: Path | None = None) -> Path:
    """Canonical write destination; resolution never creates files."""
    return _cc.project_root(Path(cwd or Path.cwd())) / ".catalyst" / "handoffs"


def tasks_dir(cwd: Path | None = None) -> Path:
    return handoffs_dir(cwd).parent / "tasks"


def legacy_dir(store: Path) -> Path:
    return store.parent.parent / ".claude" / "handoffs"


def read_path(path: Path, store: Path) -> Path:
    """Fallback only for a missing canonical brief, never escape either store."""
    if path.exists() or path.is_symlink() or path.parent != store:
        return path
    old_store = legacy_dir(store)
    old = old_store / path.name
    if old.is_file() and old.resolve().parent == old_store.resolve():
        return old.resolve()
    return path


def initialize(store: Path) -> Path:
    """Prepare a write, protecting private state before creating its directory."""
    root = store.parent.parent
    for path in (store.parent, store):
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            raise ValueError(f"Refusing unsafe state directory: {path}")
    if _git(["rev-parse", "--is-inside-work-tree"], root) == "true":
        import fcntl  # POSIX, like the plugin's bash hooks

        ignore = root / ".gitignore"
        flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK
        with os.fdopen(os.open(ignore, flags, 0o666), "a+b") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError(f"Refusing non-regular ignore file: {ignore}")
            fcntl.flock(stream, fcntl.LOCK_EX)
            stream.seek(0)
            existing = stream.read()
            rules = {b".catalyst/", b"/.catalyst/", b".catalyst", b"/.catalyst"}
            ignored = _git(["check-ignore", "--no-index", ".catalyst/"], root)
            if not rules.intersection(existing.splitlines()) or not ignored:
                stream.write((b"\n" if existing and not existing.endswith(b"\n") else b"")
                             + b".catalyst/\n")
                stream.flush()
    store.mkdir(parents=True, exist_ok=True)
    return store


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?")
    parser.add_argument("--dir", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--tasks", action="store_true", help="resolve task storage instead of checkpoints")
    parser.add_argument("--init", action="store_true", help="ensure Git ignore rule and create the store before writing")
    args = parser.parse_args()
    try:
        store = tasks_dir(args.path) if args.tasks else handoffs_dir(args.path)
        print(initialize(store) if args.init else store)
    except (OSError, ValueError) as error:
        print(f"handoff-paths: {error}", file=sys.stderr)
        sys.exit(1)
