#!/usr/bin/env python3
"""Fidelity invariant checker.

Load-bearing content (file:line pointers, fenced code, URLs, ADR/decision IDs)
must survive a rewrite (brief rebuild, brain-bridge pointer rendering). Free
content (prose) may change.

CLI:
    check-fidelity.py <reference-file> <rewritten-file>
Exit 0 if all invariants preserved, 1 if any dropped (prints them).

Importable: extract_invariants(text) -> dict, check_fidelity(ref, rewritten) -> dict.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Require a path separator before the file, so version strings (v1.2.3:45) and
# host:port (example.com:8080) are NOT treated as file:line pointers.
_POINTER_RE = re.compile(r"\b[\w.-]+/[\w./-]*[\w-]\.[A-Za-z0-9]+:\d+(?:-\d+)?")
_URL_RE = re.compile(r"https?://[^\s)\]]+")
_ID_RE = re.compile(r"\bADR-\d+\b")
_FENCE_RE = re.compile(r"```[\w-]*\n.*?\n```", re.DOTALL)


def extract_invariants(text: str) -> dict[str, list[str]]:
    return {
        "pointers": sorted(set(_POINTER_RE.findall(text))),
        "urls": sorted(set(_URL_RE.findall(text))),
        "ids": sorted(set(_ID_RE.findall(text))),
        "fences": _FENCE_RE.findall(text),
    }


def check_fidelity(reference: str, rewritten: str) -> dict[str, list[str]]:
    ref = extract_invariants(reference)
    missing: dict[str, list[str]] = {}
    for key in ("pointers", "urls", "ids"):
        missing[key] = [item for item in ref[key] if item not in rewritten]
    missing["fences"] = [f for f in ref["fences"] if f not in rewritten]
    return missing


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: check-fidelity.py <reference-file> <rewritten-file>", file=sys.stderr)
        return 2
    ref = Path(argv[1]).read_text(encoding="utf-8")
    new = Path(argv[2]).read_text(encoding="utf-8")
    missing = check_fidelity(ref, new)
    dropped = {k: v for k, v in missing.items() if v}
    if dropped:
        print("FIDELITY FAIL — dropped invariants:", file=sys.stderr)
        for kind, items in dropped.items():
            for item in items:
                print(f"  - {kind}: {item}", file=sys.stderr)
        return 1
    print("FIDELITY OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
