---
description: Dispatch a fresh-context evaluator against a domain rubric. Bundled domains: code-quality, ui-design, prose, security, performance, accessibility. Each dispatch enforces the anti-self-grade rule. Use to score an artifact when PIPELINE mode reaches an evaluator stage, or as a standalone quality gate.
---

Invoke the `evaluator-library` skill.

Recognized sub-commands (parse `$ARGUMENT`):

- `list` — List the available domains. Read `skills/evaluator-library/evaluators/*.md` (bundled) and `.claude/evaluator-library/evaluators/*.md` (user) and print the union with bundled / user labels.
- `run <domain> <artifact>` — Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-evaluator.sh <domain> <artifact>`, capture the brief, then dispatch a fresh Agent subagent with that brief. Wait for the evaluator's eval-report.md to land at `.claude/eval-reports/<domain>-<ts>.md`. Print the verdict line back to the user.
- `run <domain> <artifact> --contract <path>` — Same as above but pass the contract path as the third argument to dispatch-evaluator.sh.
- `show-rubric <domain>` — Print the contents of `skills/evaluator-library/evaluators/<domain>.md` (preferring user override at `.claude/evaluator-library/evaluators/<domain>.md` if present).

When dispatching the Agent subagent for `run`, you MUST:
- Use the Agent tool with `subagent_type: "general-purpose"` (or `claude` if available)
- Pass the brief from dispatch-evaluator.sh stdout as the `prompt`
- NEVER include the current session transcript, prior messages, or session_id in the prompt
- Set the agent's expectation that it Read the artifact, score it against the rubric, write the report, and return the verdict only

If `$ARGUMENT` is empty or unrecognized, summarize the skill: what evaluator-library does, list the 6 bundled domains, point at `skills/evaluator-library/SKILL.md` for full docs.
