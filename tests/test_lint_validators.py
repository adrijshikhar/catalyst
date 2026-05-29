"""Unit tests for the deterministic validators added to scripts/lint.py."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"

# Load scripts/lint.py as a module (it has no package).
_spec = importlib.util.spec_from_file_location("catalyst_lint", ROOT / "scripts" / "lint.py")
lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint)


class TestInvisibleUnicode(unittest.TestCase):
    def test_flags_zero_width_space(self):
        errors: list[str] = []
        lint.scan_invisible_unicode(FIXTURES / "bad_unicode.md", errors)
        self.assertTrue(any("invisible" in e.lower() or "U+200B" in e for e in errors))

    def test_clean_text_passes(self):
        errors: list[str] = []
        lint.scan_invisible_unicode(ROOT / "README.md", errors)
        self.assertEqual(errors, [])


class TestBlockScalarGuard(unittest.TestCase):
    def test_flags_literal_block_scalar(self):
        errors: list[str] = []
        lint.check_description_scalar(FIXTURES / "bad_blockscalar.md", errors)
        self.assertTrue(any("block scalar" in e.lower() for e in errors))


class TestNoPersonalPaths(unittest.TestCase):
    def test_flags_users_path(self):
        errors: list[str] = []
        text = "see /Users/nemesis/Projects/foo for details"
        lint.scan_personal_paths_text("dummy.md", text, errors)
        self.assertTrue(any("personal path" in e.lower() for e in errors))

    def test_allowlisted_placeholder_passes(self):
        errors: list[str] = []
        text = "put it under /Users/you/project"
        lint.scan_personal_paths_text("dummy.md", text, errors)
        self.assertEqual(errors, [])


class TestSettingsHookSchema(unittest.TestCase):
    def test_legacy_shape_flagged(self):
        errors: list[str] = []
        data = {"hooks": {"Stop": [{"command": "bash x.sh"}]}}
        lint.validate_hook_settings_obj(data, "settings.json", errors)
        self.assertTrue(any("hooks" in e for e in errors))

    def test_valid_shape_passes(self):
        errors: list[str] = []
        data = {"hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "bash x.sh"}]}]}}
        lint.validate_hook_settings_obj(data, "settings.json", errors)
        self.assertEqual(errors, [])


class TestFileRefResolution(unittest.TestCase):
    def test_dead_ref_flagged(self):
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "see [x](./does-not-exist-xyz.md)", ROOT, errors)
        self.assertTrue(any("unresolved" in e.lower() for e in errors))

    def test_existing_ref_passes(self):
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "see [readme](./README.md)", ROOT, errors)
        self.assertEqual(errors, [])

    def test_bare_path_not_matched(self):
        # Bare paths (prose / code fences / JSON data) are intentionally ignored.
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "run ./nonexistent-bare.md now", ROOT, errors)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
