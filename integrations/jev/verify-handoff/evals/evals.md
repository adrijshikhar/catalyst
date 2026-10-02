# Verify-handoff behavioral checks

Run each prompt in `evals.json` in a fresh agent context with Catalyst's
handoff skill and, for the integration run, `verify-handoff/SKILL.md`.
Use the supplied Jev responses as simulated tool results. Do not make live
API calls. Hide `expected` until the action trace is complete.

Inspect tool choices, final claim wording, `state.open_risks`, schema validation,
and the confirmation. All ten scenarios must meet their expected behavior.
These are dry-run behavioral checks, not live MCP or file-write integration tests.
Catalyst's deterministic gate remains `bash scripts/test.sh`.

For an actual end-to-end check, use an isolated project with Catalyst and Jev
configured, run the supported and unavailable scenarios, validate the saved
brief with Catalyst's validator, and inspect both the brief and narrative.
Record live results separately; simulated responses cannot prove API availability.

## Local check — 2026-09-25

A fresh-agent baseline using only Catalyst preserved cautious claim wording
but had no Jev invocation contract or required failure disclosure. A separate
fresh agent then traced all five scenarios with this integration: supported
claims remained scoped, unsupported `auto` was not treated as approval,
unavailable Jev preserved WRITE with an explicit risk, `review` remained
unresolved, and ordinary handoffs made no Jev call. All five traces matched
the expected behavior. These were single-run simulations, not pass@3 results.

`bash scripts/test.sh` passed the existing deterministic gate. The integration's
frontmatter, local references, and text were checked with Catalyst's lint
helpers. The skill-creator quick validator was unavailable because its PyYAML
dependency is not installed; no dependency was added. Live verification was subsequently run as recorded below.


## Live check — 2026-09-25

[Captured request and response](live-result.json): the real `jev_verify` MCP
call used `jev-latest` with output from a fresh renderer-test run (36 tests,
exit 0). Jev returned `verified` / `auto` / confidence 1.0 for that scoped
claim and `unsupported` / `auto` / confidence 0.98 for an entire-suite claim.
Only the renderer-run evidence was submitted; the earlier full-suite run
was intentionally outside this request.

In an isolated temporary Git repository, Catalyst initialized ignored storage,
validated and published a checkpoint retaining the scoped result and recording
the unsupported claim in `open_risks`, wrote a matching narrative, and rendered
the checkpoint without drift warnings. Post-write schema validation, JSON
round-trip equality, narrative header, ignore coverage, and rendered claim/risk
assertions passed. The initial draft put explanatory text in the `tests.result`
enum; the validator rejected it before publication. It was corrected to `pass`
and the explanation moved to `diff_summary` before validation and saving.

This was a live MCP call plus an agent-driven write/render smoke check, not an
automated host skill-discovery test. Service outages and review verdicts remain
covered by the simulated scenarios; no live outage was induced.

## Project opt-in routing — 2026-09-25

Added five scenarios before changing the skills: project-enabled WRITE,
missing optional skill, explicit skip, direct entry with project opt-in, and
READ with opt-in. The baseline inspection found no config routing or explicit
re-entry guard. A fresh evaluator then traced all ten scenarios before reading
their expectations; all matched, including one verification attempt and one
core-owned checkpoint/narrative publication per WRITE. These are simulated
instruction-following checks, not live host-discovery tests.

The actual configuration CLI passed isolated checks for absent configuration,
project opt-in, environment precedence, malformed and structured values,
unknown values, and main-worktree configuration from a linked worktree.
All 167 Python unit tests and the hook/config/catalog shell suites passed.
The core handoff eval snapshots were regenerated after the SKILL.md change;
the earlier live Jev result above predates automatic routing.

A subsequent live opt-in smoke check used a fresh agent and temporary Git
project with `handoff.verification: "jev"` and the optional skill installed in
the fixture's `.agents/skills/`. Asked to write an ordinary handoff after running
`python3 check.py`, the agent read the setting, loaded the optional skill, and
made one real `jev_verify` call through the existing user-configured connection.
Both submitted claims (check outcome and captured Git state) were verified with
`auto` and confidence 1. Independent artifact checks confirmed one checkpoint,
one narrative entry, successful schema validation, and unchanged project config.
The unborn branch's missing HEAD was recorded as a risk, not fabricated.
No credentials were read, copied, or embedded in the integration.


## Initial Jev grading — 2026-09-25

[Jev judgments and manual adjudication](jev-eval-results.json) cover run 0 of
all 19 refreshed core handoff scenarios. Inputs were the expected assertions,
captured artifact contents, assistant tool calls, and final responses. The
initial manual export omitted tool-result messages that the runner retained.
That export error cannot establish that a command failed. Jev graded evidence; it did not execute
the workflows. The normal CLI independently executed all 19 scenarios three
times, and the refreshed snapshots are stored alongside the core evals.

Across two live Jev calls: 13 `verified`, 6 `contradicted`; 10 judgments had
`action: review` (including some verified verdicts). This is not a pass rate.
Manual checks confirmed an inline-brief format miss (eval 24 omits Acceptance)
and an existing fixture weakness (eval 20 assumes a historical SHA unavailable
in its isolated repository; substring assertions accept a report saying no
count was available). Eval 21's contradiction is not established because the
prompt does not request the scaffold in the report and raw tool output was not
included. Low-confidence flags remain advisory, not confirmed regressions.

Eval 29 exposed an overly literal confirmation assertion: every sample asked
“Want me to delete …?” and preserved the files. Added that wording to the
accepted alternatives, preserving the file-retention assertions and all
prompts/fixture inputs. No sample was rerun to obtain a preferred judgment.

Before the fixes below, `bash scripts/test.sh` passed, including 167 Python tests, shell suites,
and enforced snapshot grading. Capability pass@3 is 17/18 (0.944, threshold
0.90); regression pass^3 is 1.00. At that point eval 24 remained a capability miss and the commit-drift fixture
weakness was unresolved. Both motivated the follow-up fixes below.


## Fixes and reproducible Jev evidence

The inline request bypassed the skill in all three failing runs. Updating the
skill description alone did not fix Claude's command entry point. The command's
description now explicitly covers inline/read-only/no-launch handoffs and loads
the skill file directly. Three fresh inline runs invoked the skill and included
both Acceptance checklist and Return instructions.

Eval 20 now prepares a disposable local Git history with a `brief-base` tag and
exactly one subsequent commit. It records that actual SHA and worktree in the
brief. Output-line assertions accept Markdown wrappers but reject a sentence merely
quoting a missing-count message. A deterministic test checks real rendering,
schema validity, and setup idempotence.

Prepare a request for one captured run with one claim per assertion:

```bash
python3 integrations/jev/verify-handoff/evals/prepare.py --eval 20 --run 0 > /tmp/jev-eval.json
```

Review the JSON, then pass its `claims` and `evidence` to the host's `jev_verify`
tool through the user's own connection. The script performs no network calls
and reads no credentials. `--snapshots` selects another captured snapshot
folder. It preserves assistant text, tool calls, tool results (including errors),
final output, artifact contents, and snapshot metadata; it omits internal thinking,
repeated usage metadata, and duplicate skill-instruction messages. Oversized
requests must be narrowed to relevant evidence, never silently truncated.

[Follow-up live judgments](jev-fix-results.json) record the fixed inline case,
the corrected clean-resume evidence, and the new commit-drift fixture. The clean
case is evidence correction, not a behavior change or a retry for a nicer score.


Follow-up validation: the inline and commit-drift cases passed 3/3 executions.
All 18 capability scenarios passed within three attempts, and the regression
scenario passed all three attempts. The live per-assertion Jev checks supported
2/2 inline assertions, 3/3 corrected clean-resume assertions, and 4/4 repaired
drift assertions without review flags. The initial literal-command rubric was
too strict about a shell-prompt prefix; Jev also missed that literal mismatch.
The final deterministic rubric accepts Markdown output wrappers and checks the
review command as text, while retaining the regression against negated counts.

Final `bash scripts/test.sh` passed with 170 unit tests, all shell suites, and
the refreshed enforced snapshot gate. `git diff --check` also passed.
