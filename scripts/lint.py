#!/usr/bin/env python3
"""Validate Catalyst plugin structure.

Checks:
- .claude-plugin/plugin.json is valid JSON with required fields
- .claude-plugin/marketplace.json is valid JSON with required fields
- Every skills/*/SKILL.md has YAML frontmatter with `name` and `description`
- Every commands/*.md has YAML frontmatter with `description`

Exit code 0 on success, 1 on any failure. Prints all failures before exiting.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def fail(msg: str, errors: list[str]) -> None:
    errors.append(msg)


def parse_frontmatter(path: Path) -> dict[str, str] | None:
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER_RE.match(text)
    if not match:
        return None
    block = match.group(1)
    result: dict[str, str] = {}
    current_key: str | None = None
    for line in block.splitlines():
        if not line.strip():
            continue
        if line.startswith(" ") and current_key is not None:
            result[current_key] += " " + line.strip()
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        result[key] = value
        current_key = key
    return result


def check_json(path: Path, required: list[str], errors: list[str]) -> None:
    if not path.exists():
        fail(f"{path.relative_to(ROOT)}: missing", errors)
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)}: invalid JSON — {exc}", errors)
        return
    for field in required:
        if field not in data:
            fail(f"{path.relative_to(ROOT)}: missing required field `{field}`", errors)


def check_skills(errors: list[str]) -> None:
    skills_dir = ROOT / "skills"
    if not skills_dir.is_dir():
        fail("skills/ directory missing", errors)
        return
    found = False
    for skill_md in skills_dir.glob("*/SKILL.md"):
        found = True
        fm = parse_frontmatter(skill_md)
        rel = skill_md.relative_to(ROOT)
        if fm is None:
            fail(f"{rel}: missing YAML frontmatter", errors)
            continue
        for field in ("name", "description"):
            if not fm.get(field):
                fail(f"{rel}: frontmatter missing `{field}`", errors)
    if not found:
        fail("skills/: no SKILL.md files found", errors)


def check_commands(errors: list[str]) -> None:
    commands_dir = ROOT / "commands"
    if not commands_dir.is_dir():
        return
    for cmd_md in commands_dir.glob("*.md"):
        fm = parse_frontmatter(cmd_md)
        rel = cmd_md.relative_to(ROOT)
        if fm is None:
            fail(f"{rel}: missing YAML frontmatter", errors)
            continue
        if not fm.get("description"):
            fail(f"{rel}: frontmatter missing `description`", errors)


HOOK_PREFIXES = (
    "PreToolUse-",
    "PostToolUse-",
    "PreCompact-",
    "SessionStart-",
    "Stop-",
    "UserPromptSubmit-",
    "SubagentStop-",
    "Notification-",
)


def check_hooks(errors: list[str]) -> None:
    hooks_dir = ROOT / "hooks"
    if not hooks_dir.is_dir():
        return
    bash_available = shutil.which("bash") is not None
    for hook_sh in hooks_dir.glob("*.sh"):
        rel = hook_sh.relative_to(ROOT)
        if not any(hook_sh.name.startswith(prefix) for prefix in HOOK_PREFIXES):
            fail(
                f"{rel}: filename must start with one of {', '.join(HOOK_PREFIXES)}",
                errors,
            )
        if bash_available:
            result = subprocess.run(
                ["bash", "-n", str(hook_sh)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                stderr = result.stderr.strip() or result.stdout.strip()
                fail(f"{rel}: bash syntax error — {stderr}", errors)


def main() -> int:
    errors: list[str] = []
    check_json(
        ROOT / ".claude-plugin" / "plugin.json",
        ["name", "version", "description", "license"],
        errors,
    )
    check_json(
        ROOT / ".claude-plugin" / "marketplace.json",
        ["name", "owner", "plugins"],
        errors,
    )
    check_skills(errors)
    check_commands(errors)
    check_hooks(errors)

    if errors:
        print("Catalyst lint: FAILED", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("Catalyst lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
