import importlib.util
import json
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


AGY_EVENTS = "\n".join([
    '{"event":"init","init":{"model":"gemini-3.8-flash-low","cwd":"/ws","tools":["run_command"]}}',
    '{"event":"step_update","step_update":{"step_index":0,"state":"DONE","step_type":"user_input"}}',
    '{"event":"step_update","step_update":{"step_index":1,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"pwd"}}}}',
    '{"event":"step_update","step_update":{"step_index":1,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"pwd"},"output":"/ws\\n"}}}',
    '{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"invoke_subagent","tool_info":{"name":"invoke_subagent","parameters":{"Task":"x"}}}}',
    '{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"invoke_subagent","tool_info":{"name":"invoke_subagent","parameters":{"Task":"x"},"output":"done"}}}',
    '{"event":"step_update","step_update":{"step_index":3,"state":"ACTIVE","step_type":"agent_response","text_delta":"Resumed from "}}',
    '{"event":"step_update","step_update":{"step_index":3,"state":"DONE","step_type":"agent_response","text_delta":"feat-x."}}',
    '{"event":"result","result":{"status":"SUCCESS","response":"Resumed from feat-x."}}',
])


class TestNormalizeAntigravity(unittest.TestCase):
    def setUp(self):
        self.lines = [json.loads(l) for l in eval_run.normalize_antigravity(AGY_EVENTS).splitlines()]

    def test_text_deltas_join_into_one_assistant_turn(self):
        texts = [c["text"] for l in self.lines if l["type"] == "assistant" for c in l["message"]["content"] if c["type"] == "text"]
        self.assertEqual(texts, ["Resumed from feat-x."])

    def test_tool_use_and_result_pairs(self):
        uses = [c for l in self.lines if l["type"] == "assistant" for c in l["message"]["content"] if c["type"] == "tool_use"]
        self.assertEqual([u["name"] for u in uses], ["run_command", "Agent"])
        self.assertEqual(uses[1]["host_tool"], "invoke_subagent")
        results = [c["content"] for l in self.lines if l["type"] == "user" for c in l["message"]["content"]]
        self.assertEqual(results, ["/ws\n", "done"])

    def test_define_subagent_is_not_a_dispatch(self):
        t = eval_run.normalize_antigravity('{"event":"step_update","step_update":{"step_index":1,"state":"ACTIVE","step_type":"tool","tool_name":"define_subagent","tool_info":{"name":"define_subagent","parameters":{}}}}')
        names = [c["name"] for l in t.splitlines() for c in json.loads(l).get("message", {}).get("content", []) if c.get("type") == "tool_use"]
        self.assertEqual(names, ["define_subagent"])

    def test_subagent_step_is_a_dispatch(self):
        raw = "\n".join([
            '{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"subagent","tool_name":"invoke_subagent","subagent_info":{"subagents":[{"role":"r","initial_prompt":"p"}]}}}',
            '{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"subagent","tool_name":"invoke_subagent","subagent_info":{"subagents":[{"role":"r"}]}}}',
        ])
        lines = [json.loads(l) for l in eval_run.normalize_antigravity(raw).splitlines()]
        uses = [c for l in lines if l["type"] == "assistant" for c in l["message"]["content"] if c["type"] == "tool_use"]
        self.assertEqual([(u["name"], u["host_tool"]) for u in uses], [("Agent", "invoke_subagent")])
        self.assertTrue(any(l["type"] == "user" for l in lines))

    def test_result_line_carries_host_and_status(self):
        r = self.lines[-1]
        self.assertEqual((r["type"], r["host"], r["is_error"], r["result"]), ("result", "antigravity", False, "Resumed from feat-x."))

    def test_error_result_with_no_work_is_infra_failure(self):
        t = eval_run.normalize_antigravity('{"event":"result","result":{"status":"FAILED","response":""}}')
        self.assertIn("agy", eval_run.infra_failure(t) or "")


if __name__ == "__main__":
    unittest.main()
