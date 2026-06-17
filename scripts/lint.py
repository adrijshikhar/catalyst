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


# --- Deterministic validators (Task 1) ---------------------------------------

# Dangerous invisible / smuggling code points. Tag block U+E0000-E007F is the
# ASCII-smuggling prompt-injection vector. Allow ©®™ (handled by not listing them).
_DANGEROUS_CODEPOINTS = (
    (0x200B, 0x200D),  # zero-width space/non-joiner/joiner
    (0xFEFF, 0xFEFF),  # BOM / zero-width no-break space
    (0x202A, 0x202E),  # bidi embedding/override
    (0x2066, 0x2069),  # bidi isolates
    (0x2061, 0x2064),  # invisible math operators
    (0xFE00, 0xFE0F),  # variation selectors
    (0xE0000, 0xE007F),  # Unicode Tag block (ASCII smuggling)
    (0x180E, 0x180E),  # Mongolian vowel separator
    (0x115F, 0x1160),  # Hangul fillers
    (0x3164, 0x3164),  # Hangul filler
)

TEXT_SUFFIXES = {".md", ".sh", ".py", ".json", ".txt", ".yml", ".yaml"}


def _is_dangerous_codepoint(cp: int) -> bool:
    return any(lo <= cp <= hi for lo, hi in _DANGEROUS_CODEPOINTS)


def scan_invisible_unicode(path: Path, errors: list[str]) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return
    for idx, ch in enumerate(text):
        cp = ord(ch)
        if _is_dangerous_codepoint(cp):
            line = text.count("\n", 0, idx) + 1
            rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
            fail(f"{rel}:{line}: invisible/dangerous code point U+{cp:04X}", errors)
            return  # one finding per file is enough to fail


_BLOCK_SCALAR_RE = re.compile(r"^[|>][+-]?\d*\s*$")


def check_description_scalar(path: Path, errors: list[str]) -> None:
    """Fail if frontmatter `description:` uses a literal/folded block scalar."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return
    match = FRONTMATTER_RE.match(text)
    if not match:
        return
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if stripped.startswith("description:"):
            value = stripped.partition(":")[2].strip()
            if _BLOCK_SCALAR_RE.match(value):
                rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
                fail(
                    f"{rel}: description uses block scalar '{value}' — "
                    "use an inline or folded '>' string (breaks catalog tables)",
                    errors,
                )
            return


_PERSONAL_PATH_RE = re.compile(r"/Users/([A-Za-z][\w.-]*)|[A-Za-z]:\\Users\\([A-Za-z][\w.-]*)")
_PATH_ALLOWLIST = {"example", "you", "user", "me", "yourname", "username"}


def scan_personal_paths_text(label: str, text: str, errors: list[str]) -> None:
    for m in _PERSONAL_PATH_RE.finditer(text):
        name = m.group(1) or m.group(2) or ""
        if name.lower() in _PATH_ALLOWLIST:
            continue
        fail(f"{label}: leaked personal path '{m.group(0)}'", errors)
        return


def validate_hook_settings_obj(data: dict, label: str, errors: list[str]) -> None:
    """Validate settings.json hooks use the matcher + hooks[] schema."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event, entries in hooks.items():
        if not isinstance(entries, list):
            fail(f"{label}: hooks.{event} must be an array", errors)
            continue
        for i, entry in enumerate(entries):
            inner = entry.get("hooks") if isinstance(entry, dict) else None
            if not isinstance(inner, list):
                fail(
                    f"{label}: hooks.{event}.{i}.hooks must be an array "
                    "(legacy {command} shape is invalid)",
                    errors,
                )
                continue
            for j, h in enumerate(inner):
                if not isinstance(h, dict) or "command" not in h:
                    fail(f"{label}: hooks.{event}.{i}.hooks.{j} missing command", errors)


# Markdown link targets only: [text](./path) or [text](../path). Bare paths in
# prose / code fences / JSON data are intentionally NOT matched (too noisy).
_FILE_REF_RE = re.compile(r"\]\((\.{1,2}/[\w./-]+\.(?:md|sh|py|json))(?:#[\w-]+)?\)")
_FENCE_STRIP_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_STRIP_RE = re.compile(r"`[^`]*`")


def check_file_refs_text(label: str, text: str, base: Path, errors: list[str]) -> None:
    # Strip fenced + inline code so illustrative example links inside code
    # spans are not treated as real navigable references.
    stripped = _FENCE_STRIP_RE.sub("", text)
    stripped = _INLINE_CODE_STRIP_RE.sub("", stripped)
    for m in _FILE_REF_RE.finditer(stripped):
        ref = m.group(1)
        target = (base / ref).resolve()
        if not target.exists():
            fail(f"{label}: unresolved file reference '{ref}'", errors)


def filter_gitignored(paths: list[Path], errors: list[str]) -> list[Path]:
    """Drop paths git would ignore (e.g., skills/*-workspace/, .claude/).

    Fail-open: if git is unavailable, return paths unchanged."""
    if shutil.which("git") is None or not paths:
        return paths
    rels = [str(p.relative_to(ROOT)) for p in paths]
    try:
        result = subprocess.run(
            ["git", "-C", str(ROOT), "check-ignore", "--stdin"],
            input="\n".join(rels),
            capture_output=True,
            text=True,
        )
    except OSError:
        return paths
    # git check-ignore: exit 0 = some ignored, 1 = none ignored, >=2 = error
    # (e.g. not a git checkout). Fail-open on error so an exported tarball
    # doesn't start scanning what would normally be gitignored scratch.
    if result.returncode >= 2:
        return paths
    ignored = set(result.stdout.splitlines())
    return [p for p, rel in zip(paths, rels) if rel not in ignored]


# --- Catalog / drift gate (Task 2) -------------------------------------------

# README skill-table rows look like:  | [`skill-name`](./skills/...) | ... |
_README_SKILL_ROW_RE = re.compile(r"^\|\s*\[`[^`]+`\]\(\./skills/", re.MULTILINE)

# Capture the skill NAME from a README skill-table row: | [`name`](./skills/...)
_README_SKILL_NAME_RE = re.compile(r"^\|\s*\[`([^`]+)`\]\(\./skills/", re.MULTILINE)


def count_skills(root: Path) -> int:
    return sum(1 for _ in (root / "skills").glob("*/SKILL.md"))


def count_commands(root: Path) -> int:
    d = root / "commands"
    return sum(1 for _ in d.glob("*.md")) if d.is_dir() else 0


def check_catalog_counts(root: Path, errors: list[str]) -> None:
    readme = root / "README.md"
    if not readme.exists():
        return
    text = readme.read_text(encoding="utf-8")
    readme_names = set(_README_SKILL_NAME_RE.findall(text))
    skill_names = {p.parent.name for p in (root / "skills").glob("*/SKILL.md")}
    missing = skill_names - readme_names
    orphan = readme_names - skill_names
    if missing:
        fail(
            "README.md: skills-table missing rows for: "
            + ", ".join(sorted(missing))
            + " — add them",
            errors,
        )
    if orphan:
        fail(
            "README.md: skills-table has rows for non-existent skills: "
            + ", ".join(sorted(orphan)),
            errors,
        )


def check_marketplace_consistency(root: Path, errors: list[str]) -> None:
    mp = root / ".claude-plugin" / "marketplace.json"
    pj = root / ".claude-plugin" / "plugin.json"
    if not (mp.exists() and pj.exists()):
        return
    try:
        mp_data = json.loads(mp.read_text())
        pj_data = json.loads(pj.read_text())
    except json.JSONDecodeError:
        return  # JSON validity already checked elsewhere
    pj_name = pj_data.get("name")
    plugins = mp_data.get("plugins", [])
    names = [p.get("name") for p in plugins if isinstance(p, dict)]
    if pj_name not in names:
        fail(
            f".claude-plugin/marketplace.json: no plugin entry named '{pj_name}' "
            "(must match plugin.json name)",
            errors,
        )


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

    # Deterministic breadth (Task 1)
    scan_targets = []
    for sub in ("skills", "commands", "hooks"):
        d = ROOT / sub
        if d.is_dir():
            for p in d.rglob("*"):
                if p.is_file() and p.suffix in TEXT_SUFFIXES:
                    scan_targets.append(p)
    for doc in ("README.md", "CLAUDE.md"):
        p = ROOT / doc
        if p.exists():
            scan_targets.append(p)

    scan_targets = filter_gitignored(scan_targets, errors)

    for p in scan_targets:
        scan_invisible_unicode(p, errors)
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scan_personal_paths_text(str(p.relative_to(ROOT)), text, errors)
        # File-ref resolution only on markdown docs — .json/.sh/.py contain data
        # paths and embedded-fixture links, not navigable doc references.
        if p.suffix == ".md":
            check_file_refs_text(str(p.relative_to(ROOT)), text, p.parent, errors)

    for skill_md in (ROOT / "skills").glob("*/SKILL.md"):
        check_description_scalar(skill_md, errors)
    for cmd_md in (ROOT / "commands").glob("*.md"):
        check_description_scalar(cmd_md, errors)

    settings = ROOT / ".claude" / "settings.json"
    if settings.exists():
        try:
            validate_hook_settings_obj(
                json.loads(settings.read_text()), ".claude/settings.json", errors
            )
        except json.JSONDecodeError:
            fail(".claude/settings.json: invalid JSON", errors)

    # Catalog / drift gate (Task 2)
    check_catalog_counts(ROOT, errors)
    check_marketplace_consistency(ROOT, errors)

    if errors:
        print("Catalyst lint: FAILED", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("Catalyst lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
