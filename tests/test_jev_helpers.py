import unittest
from scripts import jev_helpers


class TestJevHelpersTaskGate(unittest.TestCase):
    def setUp(self):
        self.sample_task = """# Task: Implement auth refresh

## Task
Add token refresh endpoint `/auth/refresh` with rotation.

## Workspace
- Current branch: `feat/auth`
- Base commit: `abcdef0`

## Acceptance checklist
- [ ] Endpoint `/auth/refresh` responds with 200 and new tokens
- [ ] Old refresh token is invalidated
- [ ] Unit tests pass

## Completion

### Status & Checklist
- [x] Implemented `/auth/refresh` endpoint with token rotation
- [x] Invalidated old refresh tokens on reuse
- [x] All 5 unit tests pass

### Verification Evidence
Ran `pytest tests/test_auth.py`:
5 passed in 0.42s
"""

    def test_prepare_task_gate_extracts_request_claims_and_evidence(self):
        payload = jev_helpers.prepare_task_gate(
            task_markdown=self.sample_task,
            git_diff="diff --git a/auth.py b/auth.py\n+def refresh(): pass\n",
            evidence="Ran pytest tests/test_auth.py: 5 passed",
        )
        self.assertIn("Add token refresh endpoint", payload["request"])
        self.assertIn("Endpoint `/auth/refresh` responds", payload["request"])
        self.assertNotIn("## Completion", payload["request"])

        self.assertIsInstance(payload["claims"], list)
        self.assertGreaterEqual(len(payload["claims"]), 2)
        self.assertTrue(any("Implemented `/auth/refresh`" in c for c in payload["claims"]))
        self.assertTrue(any("5 unit tests pass" in c for c in payload["claims"]))

        self.assertIn("diff --git", payload["diff"])
        self.assertEqual(payload["auto_accept"], 0.8)

    def test_prepare_task_gate_truncates_oversized_diff(self):
        oversized_diff = "x" * 60000
        payload = jev_helpers.prepare_task_gate(
            task_markdown=self.sample_task,
            git_diff=oversized_diff,
        )
        self.assertLessEqual(len(payload["diff"]), 50000)
        self.assertTrue(payload["diff"].endswith("\n[diff truncated]"))

    def test_prepare_task_gate_caps_evidence_characters(self):
        oversized_evidence = [{"id": "logs", "text": "log\n" * 100000}]
        payload = jev_helpers.prepare_task_gate(
            task_markdown=self.sample_task,
            git_diff="small diff",
            evidence=oversized_evidence,
        )
        total_len = sum(len(item["text"]) for item in payload["evidence"])
        self.assertLessEqual(total_len, 200000)

    def test_parse_gate_result_auto(self):
        mock_result = {
            "action": "auto",
            "safe_to_apply": 0.95,
            "composite": 0.88,
            "scores": {
                "correctness": 2,
                "spec_match": 2,
                "test_gap": 0,
                "blast_radius": 0,
            },
            "claims": [
                {"claim": "All tests pass", "verdict": "verified", "action": "auto", "confidence": 0.99}
            ]
        }
        parsed = jev_helpers.parse_gate_result(mock_result)
        self.assertEqual(parsed["action"], "auto")
        self.assertTrue(parsed["is_accepted"])
        self.assertEqual(parsed["composite"], 0.88)
        self.assertEqual(len(parsed["unresolved_claims"]), 0)

    def test_parse_gate_result_review_and_escalate(self):
        mock_result = {
            "action": "escalate",
            "safe_to_apply": 0.3,
            "composite": 0.4,
            "scores": {
                "correctness": 0,
                "spec_match": 1,
                "test_gap": 2,
                "blast_radius": 1,
            },
            "claims": [
                {"claim": "All tests pass", "verdict": "contradicted", "action": "escalate", "confidence": 0.9}
            ]
        }
        parsed = jev_helpers.parse_gate_result(mock_result)
        self.assertEqual(parsed["action"], "escalate")
        self.assertFalse(parsed["is_accepted"])
        self.assertIn("All tests pass", parsed["unresolved_claims"])

    def test_parse_gate_result_nested_live_format(self):
        nested_result = {
            "action": "auto",
            "review": {
                "safe_to_apply": 0.92,
                "composite": 0.85,
                "scores": {"correctness": 2, "spec_match": 2, "test_gap": 0, "blast_radius": 0},
            },
            "verification": {
                "results": [
                    {"claim": "All tests pass", "verdict": "verified", "action": "auto", "confidence": 0.98}
                ]
            }
        }
        parsed = jev_helpers.parse_gate_result(nested_result)
        self.assertEqual(parsed["action"], "auto")
        self.assertTrue(parsed["is_accepted"])
        self.assertEqual(parsed["safe_to_apply"], 0.92)
        self.assertEqual(parsed["composite"], 0.85)
        self.assertEqual(len(parsed["unresolved_claims"]), 0)


class TestJevHelpersDriftVerify(unittest.TestCase):
    def test_prepare_drift_verify_formats_claims_and_evidence(self):
        payload = jev_helpers.prepare_drift_verify(
            stored_sha="1111111",
            head_sha="2222222",
            decisions=["Use Redis for session store", "Fail open on network error"],
            next_acceptance_check="pytest tests/test_session.py passes",
            git_log="2222222 docs: update readme\n",
            git_diff_stat="README.md | 2 +-\n1 file changed, 1 insertion(+), 1 deletion(-)\n",
        )
        self.assertIn("claims", payload)
        self.assertIn("evidence", payload)
        self.assertEqual(len(payload["claims"]), 2)
        self.assertTrue(any("locked decisions" in c for c in payload["claims"]))
        self.assertTrue(any("next acceptance check" in c for c in payload["claims"]))

    def test_prepare_drift_verify_no_artificial_truncation(self):
        large_log = "commit\n" * 50000
        large_diff = "diff\n" * 50000
        payload = jev_helpers.prepare_drift_verify(
            stored_sha="1111111",
            head_sha="2222222",
            decisions=[],
            next_acceptance_check="tests pass",
            git_log=large_log,
            git_diff_stat=large_diff,
            diff_excerpts=large_diff,
        )
        for item in payload["evidence"]:
            self.assertFalse(item["text"].endswith("[truncated]"))
            self.assertGreater(len(item["text"]), 100000)

    def test_parse_drift_result_clean(self):
        mock_result = {
            "claims": [
                {"claim": "No conflict with locked decisions", "verdict": "verified", "action": "auto", "confidence": 0.95},
                {"claim": "Next acceptance check remains valid", "verdict": "verified", "action": "auto", "confidence": 0.92},
            ]
        }
        parsed = jev_helpers.parse_drift_result(mock_result)
        self.assertTrue(parsed["is_clean"])
        self.assertEqual(len(parsed["conflicts"]), 0)
        self.assertIn("clean", parsed["summary"].lower())

    def test_parse_drift_result_live_results_format(self):
        live_result = {
            "results": [
                {"claim": "No conflict with locked decisions", "verdict": "verified", "action": "auto"},
                {"claim": "Next acceptance check remains valid", "verdict": "verified", "action": "auto"},
            ]
        }
        parsed = jev_helpers.parse_drift_result(live_result)
        self.assertTrue(parsed["is_clean"])
        self.assertEqual(len(parsed["conflicts"]), 0)

    def test_parse_drift_result_with_conflict(self):
        mock_result = {
            "claims": [
                {"claim": "No conflict with locked decisions", "verdict": "contradicted", "action": "escalate", "confidence": 0.90},
                {"claim": "Next acceptance check remains valid", "verdict": "verified", "action": "auto", "confidence": 0.85},
            ]
        }
        parsed = jev_helpers.parse_drift_result(mock_result)
        self.assertFalse(parsed["is_clean"])
        self.assertGreater(len(parsed["conflicts"]), 0)


if __name__ == "__main__":
    unittest.main()
