---
name: verify-task
description: Use when a delegated task in .catalyst/tasks/ is completed and needs audit before integration, or when requested with Catalyst BRIEF task returns. Evaluates git diff, completion claims, and test evidence using TypeSafe Jev jev_gate.
---

# Verify a delegated Catalyst task

Check completion claims, code changes, and test evidence of a delegated Catalyst
task before accepting or integrating changes. Catalyst owns task file generation
and workspace setup; this skill provides an advisory completion gate for BRIEF
task returns using TypeSafe Jev `jev_gate`.

Use only the user's own Jev MCP connection, authenticated with their own API
key in the host's MCP configuration or secret store. Catalyst supplies no key
or shared credential service. Never ask the user to paste a key into chat,
read or copy it into evidence, or store it in Catalyst config or task files.
Authentication failures follow the unavailable-verification path below.

1. **Locate task:** Target the delegated task file under `.catalyst/tasks/`
   (e.g. `.catalyst/tasks/<task-slug>.md`). Inspect the `## Completion` section.
   If `## Completion` is absent or empty, halt and report that the task has
   not been completed by the worker.

2. **Extract inputs:**
   - **Request:** Everything preceding `## Completion` in the task file (the
     `## Task` objective, `## Workspace` requirements, and `## Acceptance checklist`).
   - **Diff:** The patch produced by the worker against the recorded base commit
     (`git diff <base_commit>..HEAD` or working tree diff). Truncated at 50,000 characters.
   - **Claims:** The completion checklist bullets and assertions from `## Completion`.
   - **Evidence:** Captured test logs, command outputs, and trace evidence recorded
     under `### Verification Evidence`. Truncated to 200,000 characters aggregate.

3. **Call Jev:** Discover the host's `jev_gate` tool (e.g. `mcp__jev__jev_gate`).
   Submit one bounded request containing `request`, `diff`, `claims`, and `evidence`.
   Do not include secrets, credentials, or unrelated project files.

4. **Interpret Gate Verdict:**
   - **`auto`**: Safe to accept. All claims verified, test gap is low, and rubric
     composite is above floor. The originating agent may proceed to report completion
     and integrate the changes within the authorized scope.
   - **`review`**: Potential gaps detected. Inspect the rubric scores (correctness,
     spec match, test gap, blast radius) and the unverified claims. Present these
     specific gaps to the user before proceeding.
   - **`escalate`**: Contradictions or failures found (e.g. claimed tests pass when
     logs show failures, or changes contradict the checklist). Do not integrate;
     relay the specific contradictions back to the worker to fix.

5. **Fail-Open Policy:** If `jev_gate` is absent, unreachable, errors, or times out:
   - Fall back to manual inspection of the diff and test output against the original checklist.
   - State clearly in the report: `Jev task verification not performed: <reason>`.
   - Never retry in an infinite loop, prompt for API keys, or install tools.
