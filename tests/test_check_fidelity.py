"""Unit tests for scripts/check-fidelity.py."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("check_fidelity", ROOT / "scripts" / "check-fidelity.py")
fid = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fid)


class TestExtractInvariants(unittest.TestCase):
    def test_extracts_file_line_pointers(self):
        inv = fid.extract_invariants("see src/auth/middleware.ts:42-78 and x.py:10")
        self.assertIn("src/auth/middleware.ts:42-78", inv["pointers"])
        self.assertIn("x.py:10", inv["pointers"])

    def test_extracts_urls_and_adr(self):
        inv = fid.extract_invariants("ADR-007 at https://example.com/x")
        self.assertIn("ADR-007", inv["ids"])
        self.assertIn("https://example.com/x", inv["urls"])


class TestCheckFidelity(unittest.TestCase):
    def test_dropped_pointer_fails(self):
        ref = "pointer src/a.ts:1-9 must survive"
        rewritten = "summary with no pointer"
        missing = fid.check_fidelity(ref, rewritten)
        self.assertIn("src/a.ts:1-9", missing["pointers"])

    def test_all_preserved_passes(self):
        ref = "src/a.ts:1-9 and ADR-007"
        rewritten = "- src/a.ts:1-9 (kept)\n- ADR-007 (kept)"
        missing = fid.check_fidelity(ref, rewritten)
        self.assertEqual(missing["pointers"], [])
        self.assertEqual(missing["ids"], [])


if __name__ == "__main__":
    unittest.main()
