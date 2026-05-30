"""Render the typed brief to resume text + mismatch guards."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
_spec = importlib.util.spec_from_file_location("handoff_render", ROOT / "scripts" / "handoff-render.py")
hr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hr)


def _valid():
    return json.loads((FIX / "brief-valid.json").read_text())


class TestRender(unittest.TestCase):
    def test_includes_key_donewhen_nextcheck(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertIn("feat-jwt-expiry", out)
        self.assertIn("pnpm test auth.spec.ts 6/6", out)
        self.assertIn("expiry uses <= not <", out)

    def test_derives_resume_prompt_when_absent(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        # derived prompt points at the durable entry point, not a relative script
        # path that only exists inside the catalyst repo (fails in consumer projects)
        self.assertIn("/catalyst:handoff resume", out)
        self.assertNotIn("scripts/handoff-render.py", out)
        self.assertIn("expiry uses <= not <", out)

    def test_uses_stored_prompt_when_present(self):
        obj = _valid(); obj["resume"]["prompt"] = "CUSTOM-RESUME-LINE"
        out = hr.render(obj, current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertIn("CUSTOM-RESUME-LINE", out)

    def test_branch_mismatch_warns(self):
        out = hr.render(_valid(), current_branch="other-branch", current_common_dir="/repo/.git")
        self.assertIn("feat/jwt-expiry", out)
        self.assertRegex(out.lower(), r"(mismatch|different branch|confirm)")

    def test_repo_mismatch_warns(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/other/.git")
        self.assertRegex(out.lower(), r"(different repo|repo mismatch|not resuming)")

    def test_shows_originating_worktree(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertIn("Written in worktree: /repo", out)

    def test_no_warnings_when_branch_and_repo_match(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertNotIn("MISMATCH", out)

    def test_repo_match_with_trailing_slash(self):
        out = hr.render(_valid(), current_branch="feat/jwt-expiry", current_common_dir="/repo/.git/")
        self.assertNotIn("REPO MISMATCH", out)

    def test_repo_match_when_brief_stored_worktree_private_dir(self):
        # Real-world: WRITE in a linked worktree recorded the worktree-private
        # git dir (<common>/.git/worktrees/<name>) instead of the shared common
        # dir. Resuming compares against `git rev-parse --git-common-dir`
        # (<common>/.git) — must NOT fire a false REPO MISMATCH.
        obj = _valid()
        obj["state"]["worktree"]["git_common_dir"] = "/repo/.git/worktrees/feat-x"
        out = hr.render(obj, current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertNotIn("REPO MISMATCH", out)

    def test_repo_match_with_relative_stored_common_dir(self):
        # Brief written in a MAIN checkout stores the relative ".git" that
        # `git rev-parse --git-common-dir` returns; resuming there must NOT
        # falsely fire REPO MISMATCH (relative is resolved against root).
        obj = _valid()
        obj["state"]["worktree"]["root"] = "/repo"
        obj["state"]["worktree"]["git_common_dir"] = ".git"
        out = hr.render(obj, current_branch="feat/jwt-expiry", current_common_dir="/repo/.git")
        self.assertNotIn("REPO MISMATCH", out)


class TestKeyPathContainment(unittest.TestCase):
    """_key_path refuses keys that escape the handoffs store (path traversal)."""

    def _with_store(self, store: Path, key: str):
        orig = hr._hp.handoffs_dir
        hr._hp.handoffs_dir = lambda *a, **k: store
        try:
            return hr._key_path(key)
        finally:
            hr._hp.handoffs_dir = orig

    def test_plain_key_resolves_inside_store(self):
        with tempfile.TemporaryDirectory() as d:
            store = Path(d)
            got = self._with_store(store, "feat-jwt-expiry")
            self.assertEqual(got, (store / "feat-jwt-expiry.json").resolve())

    def test_traversal_key_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            store = Path(d) / "handoffs"
            store.mkdir()
            self.assertIsNone(self._with_store(store, "../../../etc/passwd"))

    def test_absolute_key_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(self._with_store(Path(d), "/etc/passwd"))


if __name__ == "__main__":
    unittest.main()
