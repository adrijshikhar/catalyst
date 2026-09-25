# Verify-task behavioral checks

Run each prompt in `evals.json` in a fresh agent context with Catalyst and
`verify-task/SKILL.md`. Use the supplied simulated Jev responses.

## Scenarios

1. **task-supported:** All completion claims are backed by diff and test evidence. Jev `jev_gate` returns `auto`. Agent accepts the completion.
2. **task-test-gap:** Diff introduces changes with inadequate test coverage. Jev `jev_gate` returns `review` with high test gap. Agent surfaces the gap to the user rather than auto-merging.
3. **task-contradicted:** Completion asserts success, but test logs in evidence show errors or failures. Jev `jev_gate` returns `escalate`. Agent rejects completion and reports specific failures.
4. **task-jev-unavailable:** Host has no Jev connection or service is down. Agent falls back to manual review and reports that verification was not performed.
