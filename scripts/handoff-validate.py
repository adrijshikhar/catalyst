#!/usr/bin/env python3
"""WRITE-time validation gate for a typed handoff brief.

Hand-rolled validator against skills/handoff/brief.schema.json — a focused
subset of JSON Schema (type, required, additionalProperties=false, enum, const,
minLength, pattern). Zero deps (stdlib only). Returns a list of human-readable
errors; empty list = valid.

CLI: handoff-validate.py <brief.json>  (exit 0 valid, 1 invalid + errors)
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("handoff_paths", ROOT / "scripts" / "handoff_paths.py")
_hp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_hp)

_TYPE = {"object": dict, "array": list, "string": str, "boolean": bool}


def _check(obj, schema, path, errs):
    if "const" in schema and obj != schema["const"]:
        errs.append(f"{path}: must equal {schema['const']!r}")
        return
    if "enum" in schema and obj not in schema["enum"]:
        errs.append(f"{path}: must be one of {schema['enum']}")
        return
    t = schema.get("type")
    if t:
        expected = _TYPE[t]
        ok = isinstance(obj, expected)
        if expected is not bool and isinstance(obj, bool):
            ok = False  # bool is subclass of int but never a valid str/object/array/number here
        if not ok:
            errs.append(f"{path}: expected {t}, got {type(obj).__name__}")
            return
    if t == "string":
        if "minLength" in schema and len(obj) < schema["minLength"]:
            errs.append(f"{path}: must be a non-empty string")
        if "pattern" in schema and not re.match(schema["pattern"], obj):
            errs.append(f"{path}: does not match required format")
    elif t == "object":
        props = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in obj:
                errs.append(f"{path}.{req}: required field missing")
        if schema.get("additionalProperties") is False:
            for k in obj:
                if k not in props:
                    errs.append(f"{path}.{k}: unknown field not allowed")
        for k, v in obj.items():
            if k in props:
                _check(v, props[k], f"{path}.{k}", errs)
    elif t == "array":
        item_schema = schema.get("items")
        if item_schema:
            for i, item in enumerate(obj):
                _check(item, item_schema, f"{path}[{i}]", errs)


def validate(obj) -> list[str]:
    schema = _hp.load_schema()
    errs: list[str] = []
    _check(obj, schema, "$", errs)
    return [e.replace("$.", "").replace("$", "(root)") for e in errs]


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: handoff-validate.py <brief.json>", file=sys.stderr)
        return 2
    try:
        obj = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"handoff-validate: cannot read JSON — {e}", file=sys.stderr)
        return 1
    errs = validate(obj)
    if errs:
        print("handoff-validate: INVALID", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print("handoff-validate: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
