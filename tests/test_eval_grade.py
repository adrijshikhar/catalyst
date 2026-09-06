"""eval-grade.py: deterministic grammar over transcript + captured files."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("eval_grade", ROOT / "scripts" / "eval-grade.py")
eg = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(eg)

FILES = {
    "resume_summary.md": "Next acceptance check: 'pnpm test passes 6/6'. Read first: src/utils/logger.ts",
    ".claude/handoffs/feat-x.json": '{"schema_version":"1","key":"feat-x","timestamp":"2026-09-06T00:00:00Z","mode":"WRITE","resume":{"done_when":"d","resume_by":"r"},"state":{"branch":"feat/x","next_acceptance_check":"c","worktree":{"root":"/w","is_linked":false,"git_common_dir":"/w/.git"}},"files_read_first":[],"files_skip":[]}',
    "hooks/PostToolUse-x.sh": "#!/usr/bin/env bash\nset -euo pipefail\n# TODO custom logic\ncommand -v jq >/dev/null || exit 1\n",
}


class TestGrammar(unittest.TestCase):
    def test_exists_is_file_aware(self):
        self.assertTrue(eg.grade_assertion("resume_summary.md exists in the working directory", "", FILES))
        self.assertFalse(eg.grade_assertion("resume_response.md exists", "", FILES))

    def test_exists_falls_back_to_transcript(self):
        self.assertTrue(eg.grade_assertion("`Tier 2` exists", "chose Tier 2 (branch)", {}))

    def test_negative_file_assertion(self):
        self.assertTrue(eg.grade_assertion("Brief was NOT written to .claude/handoffs/HANDOFF.json", "", FILES))
        self.assertFalse(eg.grade_assertion("PROJECT_STATE.md was NOT created", "", {**FILES, ".claude/PROJECT_STATE.md": "x"}))

    def test_negative_without_path_is_ungraded(self):
        self.assertIsNone(eg.grade_assertion("Skill did NOT silently pick a brief without surfacing alternatives", "", FILES))

    def test_needles_all_and_any(self):
        self.assertTrue(eg.grade_assertion("mentions 'logger.ts' and '6/6'", "", FILES))
        self.assertFalse(eg.grade_assertion("mentions 'logger.ts' and 'nope'", "", FILES))
        self.assertTrue(eg.grade_assertion("contains at least one of: 'nope', 'logger.ts'", "", FILES))

    def test_exits_zero_runs_against_captured_files(self):
        self.assertTrue(eg.grade_assertion("`python3 scripts/handoff-validate.py .claude/handoffs/feat-x.json` exits 0", "", FILES))
        self.assertFalse(eg.grade_assertion("`python3 scripts/handoff-validate.py missing.json` exits 0", "", FILES))

    def test_bash_n(self):
        self.assertTrue(eg.grade_assertion("hooks/PostToolUse-x.sh passes 'bash -n' syntax check", "", FILES))

    def test_positive_written_to_path(self):
        self.assertTrue(eg.grade_assertion("Brief was written to .claude/handoffs/feat-x.json (tier 2)", "", FILES))
        self.assertFalse(eg.grade_assertion("Brief was written to .claude/handoffs/nope.json", "", FILES))

    def test_json_field_is_and_mentions(self):
        self.assertTrue(eg.grade_assertion("Brief state.branch is feat/x", "", FILES))
        self.assertFalse(eg.grade_assertion("Brief state.branch is main", "", FILES))
        self.assertTrue(eg.grade_assertion("Brief state.next_acceptance_check mentions 'c'", "", FILES))

    def test_subject_file_needles(self):
        self.assertTrue(eg.grade_assertion("resume_summary.md names src/utils/logger.ts as a file to read first", "", FILES))
        self.assertTrue(eg.grade_assertion("resume_summary.md quotes the next acceptance check: 'pnpm test passes 6/6'", "", FILES))
        self.assertFalse(eg.grade_assertion("resume_summary.md quotes 'nothing here'", "", FILES))

    def test_rendered_output_contains(self):
        self.assertTrue(eg.grade_assertion("The rendered output of `python3 scripts/handoff-render.py --file .claude/handoffs/feat-x.json` contains 'c'", "", FILES))

    def test_chat_response_phrase(self):
        self.assertTrue(eg.grade_assertion("Chat response names tier 2 (branch) as the resolution chosen", "I chose Tier 2 (branch key).", {}))
        self.assertFalse(eg.grade_assertion("Chat response names tier 3 (legacy) as the resolution chosen", "I chose Tier 2.", {}))

    def test_prose_only_is_ungraded(self):
        self.assertIsNone(eg.grade_assertion("Chosen brief is feat-jwt-expiry (matches current branch)", "", FILES))


class TestSummary(unittest.TestCase):
    def test_passk_and_spread(self):
        s = eg.summarize([1.0, 0.5, 1.0])
        self.assertEqual(s["pass_at_3"], 1.0); self.assertEqual(s["pass_caret_3"], 0.0); self.assertEqual(s["pass_at_1"], 1.0)
        self.assertAlmostEqual(s["median"], 1.0); self.assertGreater(s["stdev"], 0)


if __name__ == "__main__":
    unittest.main()
