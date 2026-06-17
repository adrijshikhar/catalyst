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


class TestReground(unittest.TestCase):
    def test_reground_includes_loadbearing_excludes_narrative(self):
        obj = _valid()
        # Enrich with optional load-bearing fields so we can assert they appear
        obj["state"]["decisions"] = ["use <= for expiry boundary check"]
        obj["files_read_first"] = [{"path": "src/auth/middleware.ts", "why": "contains the expiry logic"}]

        out = hr.render_reground(obj)

        # --- load-bearing inclusions ---
        # next_acceptance_check from state (fixture value: "expiry uses <= not <")
        self.assertIn("expiry uses <= not <", out)
        # done_when from resume (fixture value: "pnpm test auth.spec.ts 6/6")
        self.assertIn("pnpm test auth.spec.ts 6/6", out)
        # at least one decisions entry
        self.assertIn("use <= for expiry boundary check", out)
        # files_read_first path
        self.assertIn("src/auth/middleware.ts", out)

        # --- resume-scaffold exclusions ---
        # reground is NOT a resume — must not contain full resume boilerplate
        self.assertNotIn("## Summary", out)
        self.assertNotIn("Written in worktree", out)
        # must not contain mismatch blocks (no branch/repo context needed for reground)
        self.assertNotIn("REPO MISMATCH", out)
        self.assertNotIn("BRANCH MISMATCH", out)


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

    def test_dotjson_suffix_key_does_not_double_append(self):
        # A caller passing "<key>.json" must resolve to <store>/<key>.json,
        # NOT <store>/<key>.json.json (the fortress-session render footgun).
        with tempfile.TemporaryDirectory() as d:
            store = Path(d)
            got = self._with_store(store, "feat-jwt-expiry.json")
            self.assertEqual(got, (store / "feat-jwt-expiry.json").resolve())

    def test_absolute_path_inside_store_resolves(self):
        # A full absolute path to a brief already inside the store must resolve
        # to itself (the skill/agent sometimes passes the path, not the key).
        with tempfile.TemporaryDirectory() as d:
            store = Path(d)
            full = store / "feat-jwt-expiry.json"
            got = self._with_store(store, str(full))
            self.assertEqual(got, full.resolve())


if __name__ == "__main__":
    unittest.main()
