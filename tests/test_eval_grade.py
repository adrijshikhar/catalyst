"""Unit tests for scripts/eval-grade.py deterministic grading."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("eval_grade", ROOT / "scripts" / "eval-grade.py")
eg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(eg)


class TestAssertionGrading(unittest.TestCase):
    def test_contains_assertion_pass(self):
        self.assertTrue(eg.grade_assertion("output has '## Brain pointers'", "x\n## Brain pointers\ny"))

    def test_contains_assertion_fail(self):
        self.assertFalse(eg.grade_assertion("output has '## Missing'", "no such section"))

    def test_exists_assertion(self):
        self.assertTrue(eg.grade_assertion("brief.md exists", "brief.md exists"))


class TestStats(unittest.TestCase):
    def test_passk_and_spread(self):
        stats = eg.summarize([1.0, 0.0, 1.0])  # 3 runs, 2 pass
        self.assertAlmostEqual(stats["pass_at_1"], 1.0)  # first run passed
        self.assertAlmostEqual(stats["pass_at_3"], 1.0)  # at least one of 3 passed
        self.assertEqual(stats["n"], 3)
        self.assertIn("stdev", stats)
        self.assertIn("median", stats)


if __name__ == "__main__":
    unittest.main()
