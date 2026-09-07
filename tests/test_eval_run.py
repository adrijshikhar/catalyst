import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("eval_run", ROOT / "scripts" / "eval-run.py")
eval_run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(eval_run)


class TestInfraFailure(unittest.TestCase):
    def test_usage_limit_is_infra_failure(self):
        t = '{"type":"assistant","message":{"content":[{"type":"text","text":"You\u2019ve hit your session limit \u00b7 resets 2:20am"}]}}\n{"type":"result","subtype":"success","is_error":true,"num_turns":1,"result":"You\u2019ve hit your session limit"}'
        self.assertIn("session limit", eval_run.infra_failure(t) or "")

    def test_login_wall_is_infra_failure(self):
        t = '{"type":"result","result":"Please run /login","total_cost_usd":0,"usage":{"output_tokens":0}}'
        self.assertIn("not authenticated", eval_run.infra_failure(t) or "")

    def test_real_run_is_not_infra_failure(self):
        t = '{"type":"assistant","message":{"content":[{"type":"text","text":"The rate limit middleware is done."}]}}\n{"type":"result","subtype":"success","is_error":false,"num_turns":9,"result":"done"}'
        self.assertIsNone(eval_run.infra_failure(t))


if __name__ == "__main__":
    unittest.main()
