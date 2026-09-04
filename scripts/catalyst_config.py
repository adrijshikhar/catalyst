#!/usr/bin/env python3
"""Shared config reader: env > .claude/catalyst.json > default.

Mirrors hooks/lib/config.sh — the two are held together by
tests/test_catalyst_config.py::TestParity. Change one, change both.

Env-name rule: CATALYST_ + dotted key uppercased with '.' -> '_'.
Structured values (arrays/objects) have no env form; read them with get_json().
Zero deps (stdlib only).
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


def env_name(key: str) -> str:
    return "CATALYST_" + key.upper().replace(".", "_")


def _git(args: list[str], cwd: Path) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                           text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def project_root(cwd: Path | None = None) -> Path:
    """Main-worktree root (parent of the shared .git), else cwd."""
    base = cwd or os.environ.get("CLAUDE_PROJECT_DIR") or Path.cwd()
    base = Path(base)
    common = _git(["rev-parse", "--git-common-dir"], base)
    if common:
        p = Path(common) if Path(common).is_absolute() else (base / common)
        try:
            p = p.resolve()
        except OSError:
            return base
        if p.name == ".git":
            return p.parent
    return base


def config_path(cwd: Path | None = None) -> Path:
    return project_root(cwd) / ".claude" / "catalyst.json"


def _load(cwd: Path | None = None) -> dict:
    try:
        return json.loads(config_path(cwd).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, ValueError):
        return {}


def _dig(obj: dict, key: str):
    cur = obj
    for part in key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def get(key: str, default, cwd: Path | None = None):
    """Scalar read. Returns `default` for absent keys AND for structured values
    (never stringifies a list/dict — callers would parse garbage)."""
    env = os.environ.get(env_name(key))
    if env not in (None, ""):
        return env
    val = _dig(_load(cwd), key)
    # An empty string is not a usable scalar, so it is treated as absent — the
    # bash reader cannot distinguish "" from unset (`[ -n "$val" ]`), and a
    # reader pair that disagrees is worse than one that is uniformly strict.
    if isinstance(val, str) and val == "":
        return default
    if isinstance(val, (str, int, float, bool)):
        return val
    return default


def get_json(key: str, cwd: Path | None = None):
    """Structured read — returns the parsed value or None."""
    return _dig(_load(cwd), key)
