"""Validation rules for the typed handoff brief."""
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
_spec = importlib.util.spec_from_file_location("handoff_validate", ROOT / "scripts" / "handoff-validate.py")
hv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hv)


def _load(name):
    return json.loads((FIX / name).read_text())


class TestValidate(unittest.TestCase):
    def test_valid_passes(self):
        self.assertEqual(hv.validate(_load("brief-valid.json")), [])

    def test_missing_required_field_fails(self):
        errs = hv.validate(_load("brief-missing-donewhen.json"))
        self.assertTrue(any("done_when" in e for e in errs))

    def test_unknown_top_level_key_rejected(self):
        errs = hv.validate(_load("brief-unknown-key.json"))
        self.assertTrue(any("state_packet" in e or "unknown" in e.lower() for e in errs))

    def test_empty_required_string_fails(self):
        obj = _load("brief-valid.json"); obj["state"]["next_acceptance_check"] = ""
        self.assertTrue(any("next_acceptance_check" in e for e in hv.validate(obj)))

    def test_bad_timestamp_fails(self):
        obj = _load("brief-valid.json"); obj["timestamp"] = "2026-05-30 10:00"
        self.assertTrue(any("timestamp" in e for e in hv.validate(obj)))

    def test_bad_test_result_enum_fails(self):
        obj = _load("brief-valid.json"); obj["state"]["tests"][0]["result"] = "maybe"
        self.assertTrue(any("result" in e for e in hv.validate(obj)))

    def test_bad_mode_enum_fails(self):
        obj = _load("brief-valid.json"); obj["mode"] = "READ"
        self.assertTrue(any("mode" in e for e in hv.validate(obj)))


class TestHeadShaField(unittest.TestCase):
    def test_head_sha_valid_is_accepted(self):
        obj = _load("brief-valid.json"); obj["state"]["head_sha"] = "a1b2c3d"
        self.assertEqual(hv.validate(obj), [])

    def test_head_sha_bad_pattern_rejected(self):
        obj = _load("brief-valid.json"); obj["state"]["head_sha"] = "XYZ!!"
        self.assertTrue(any("head_sha" in e for e in hv.validate(obj)))


if __name__ == "__main__":
    unittest.main()
