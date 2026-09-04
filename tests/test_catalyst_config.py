"""Shared config reader: precedence, structured values, bash/python parity."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "catalyst_config", ROOT / "scripts" / "catalyst_config.py")
cc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cc)

CLI = ROOT / "scripts" / "catalyst-config.sh"

# Every knob the spec's config table declares, as (key, default).
KNOBS = [
    ("handoff.stale_hours", "24"),
    ("handoff.brief_max_lines", "30"),
    ("example.nested_number", "10"),
]


def _write_config(root: Path, data: dict) -> None:
    (root / ".claude").mkdir(parents=True, exist_ok=True)
    (root / ".claude" / "catalyst.json").write_text(json.dumps(data), encoding="utf-8")


def _cli(args: list[str], cwd: Path, env: dict | None = None) -> str:
    e = dict(os.environ)
    e["CLAUDE_PROJECT_DIR"] = str(cwd)
    if env:
        e.update(env)
    r = subprocess.run(["bash", str(CLI), *args], cwd=cwd, capture_output=True,
                       text=True, env=e)
    return r.stdout.strip()


class TestEnvName(unittest.TestCase):
    def test_derives_existing_variable_name(self):
        # The rule must reproduce the variable that already ships, or the
        # v0.7 behavior silently breaks.
        self.assertEqual(cc.env_name("handoff.stale_hours"),
                         "CATALYST_HANDOFF_STALE_HOURS")

    def test_derives_nested_example_name(self):
        self.assertEqual(cc.env_name("example.nested_number"),
                         "CATALYST_EXAMPLE_NESTED_NUMBER")


class TestPrecedence(unittest.TestCase):
    def test_default_when_nothing_set(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=Path(d)), 24)

    def test_json_beats_default(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"handoff": {"stale_hours": 1}})
            self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=root), 1)

    def test_env_beats_json(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"handoff": {"stale_hours": 1}})
            os.environ["CATALYST_HANDOFF_STALE_HOURS"] = "7"
            try:
                self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=root), "7")
            finally:
                del os.environ["CATALYST_HANDOFF_STALE_HOURS"]

    def test_malformed_json_falls_back_to_default(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / ".claude").mkdir()
            (root / ".claude" / "catalyst.json").write_text("{not json", encoding="utf-8")
            self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=root), 24)

    def test_missing_key_falls_back_to_default(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"example": {"nested_number": 5}})
            self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=root), 24)


class TestStructuredValues(unittest.TestCase):
    def test_get_json_returns_array(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            claims = [{"writes_to": "x.json", "requires_read_of": ["x.log"]}]
            _write_config(root, {"example": {"items": claims}})
            self.assertEqual(cc.get_json("example.items", cwd=root), claims)

    def test_get_refuses_to_stringify_a_structure(self):
        # A scalar reader must never return "[{'writes_to'..." — callers would
        # parse garbage. It returns the default instead.
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"example": {"items": [{"writes_to": "x"}]}})
            self.assertEqual(cc.get("example.items", "FALLBACK", cwd=root),
                             "FALLBACK")

    def test_get_json_absent_returns_none(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(cc.get_json("example.items", cwd=Path(d)))

    def test_get_json_false_leaf_is_not_absent(self):
        # Finding 3: a JSON `false` leaf must come back as False, not None —
        # `null` (absent) and `false` (present, falsy) are different things.
        # The bash twin's `getpath(...) // empty` used to conflate them
        # because jq's `//` treats `false` as falsy too.
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"example": {"some_flag": False}})
            self.assertIs(cc.get_json("example.some_flag", cwd=root), False)


    def test_explicit_empty_string_treated_as_absent_in_both(self):
        """An empty string is not a usable scalar. bash cannot tell "" from unset,
        so Python matches it rather than the pair disagreeing."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"handoff": {"stale_hours": ""}})
            self.assertEqual(cc.get("handoff.stale_hours", 24, cwd=root), 24)
            self.assertEqual(str(cc.get("handoff.stale_hours", "24", cwd=root)),
                             _cli(["get", "handoff.stale_hours", "24"], root))


class TestParity(unittest.TestCase):
    def test_bash_python_agree_on_every_knob_default(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for key, default in KNOBS:
                py = str(cc.get(key, default, cwd=root))
                sh = _cli(["get", key, default], root)
                self.assertEqual(py, sh, f"default parity mismatch for {key}")

    def test_bash_python_agree_on_json_values(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"handoff": {"stale_hours": 3, "brief_max_lines": 12},
                                 "example": {"nested_number": 4}})
            for key, default in KNOBS:
                py = str(cc.get(key, default, cwd=root))
                sh = _cli(["get", key, default], root)
                self.assertEqual(py, sh, f"json parity mismatch for {key}")

    def test_bash_python_agree_on_false_leaf(self):
        # Finding 3 parity: `getpath(...) // empty` in the bash reader used
        # to drop a JSON `false` leaf silently (jq's `//` treats `false` as
        # falsy), disagreeing with the Python reader's get_json(), which
        # correctly returns False for it. Both must now emit "false".
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"example": {"some_flag": False}})
            py = json.dumps(cc.get_json("example.some_flag", cwd=root))
            sh = _cli(["json", "example.some_flag"], root)
            self.assertEqual(py, "false")
            self.assertEqual(sh, "false")
            self.assertEqual(py, sh, "bash/python disagree on a false leaf")

    def test_bash_python_agree_on_env_override(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _write_config(root, {"handoff": {"stale_hours": 3}})
            env = {"CATALYST_HANDOFF_STALE_HOURS": "9"}
            os.environ.update(env)
            try:
                py = str(cc.get("handoff.stale_hours", "24", cwd=root))
                sh = _cli(["get", "handoff.stale_hours", "24"], root, env)
                self.assertEqual(py, "9")
                self.assertEqual(py, sh)
            finally:
                del os.environ["CATALYST_HANDOFF_STALE_HOURS"]


if __name__ == "__main__":
    unittest.main()
