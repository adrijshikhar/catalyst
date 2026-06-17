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
        self.assertGreaterEqual(n, 6)  # shipped skill count (8→7 session-health merge; 7→6 brain-bridge retired 2026-06-17)

    def test_count_commands_matches_md(self):
        n = lint.count_commands(ROOT)
        self.assertGreaterEqual(n, 7)  # 8→7 after brain-bridge retired 2026-06-17

    def test_readme_skill_rows_match(self):
        errors: list[str] = []
        lint.check_catalog_counts(ROOT, errors)
        self.assertEqual(errors, [])  # repo is currently consistent

    def test_marketplace_name_consistency(self):
        errors: list[str] = []
        lint.check_marketplace_consistency(ROOT, errors)
        self.assertEqual(errors, [])

    def test_readme_missing_skill_row_is_flagged(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for s in ("foo", "bar"):
                (root / "skills" / s).mkdir(parents=True)
                (root / "skills" / s / "SKILL.md").write_text("---\nname: %s\ndescription: x\n---\n" % s)
            # README lists only foo — bar is missing.
            (root / "README.md").write_text(
                "## Skills\n\n| Skill | Purpose |\n|---|---|\n"
                "| [`foo`](./skills/foo/SKILL.md) | x |\n"
            )
            errors: list[str] = []
            lint.check_catalog_counts(root, errors)
            self.assertTrue(any("bar" in e for e in errors), errors)

    def test_readme_orphan_row_is_flagged(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "skills" / "foo").mkdir(parents=True)
            (root / "skills" / "foo" / "SKILL.md").write_text("---\nname: foo\ndescription: x\n---\n")
            # README lists foo AND a ghost skill with no dir.
            (root / "README.md").write_text(
                "## Skills\n\n| Skill | Purpose |\n|---|---|\n"
                "| [`foo`](./skills/foo/SKILL.md) | x |\n"
                "| [`ghost`](./skills/ghost/SKILL.md) | x |\n"
            )
            errors: list[str] = []
            lint.check_catalog_counts(root, errors)
            self.assertTrue(any("ghost" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
