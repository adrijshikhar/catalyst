"""Unit tests for the catalog/drift gate added to scripts/lint.py."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("catalyst_lint", ROOT / "scripts" / "lint.py")
lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint)


class TestCatalogCounts(unittest.TestCase):
    def test_count_skills_matches_dirs_with_skill_md(self):
        n = lint.count_skills(ROOT)
        self.assertGreaterEqual(n, 7)  # current shipped skill count (8→7 after session-health merge)

    def test_count_commands_matches_md(self):
        n = lint.count_commands(ROOT)
        self.assertGreaterEqual(n, 8)

    def test_readme_skill_rows_match(self):
        errors: list[str] = []
        lint.check_catalog_counts(ROOT, errors)
        self.assertEqual(errors, [])  # repo is currently consistent

    def test_marketplace_name_consistency(self):
        errors: list[str] = []
        lint.check_marketplace_consistency(ROOT, errors)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
