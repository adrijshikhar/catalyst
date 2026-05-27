---
description: Run a pipeline — either invoke handoff PIPELINE mode directly (decompose → route → brief → dispatch → synthesize) OR run / list / save a named pipeline template via pipeline-templates. Skip for trivial single-step tasks.
---

Parse `$ARGUMENT` to determine which sub-command to run:

- `list` — Invoke the `pipeline-templates` skill in LIST mode. Read `skills/pipeline-templates/templates/*.md` (bundled) and `.claude/pipelines/*.md` (user) and print the union with bundled / user labels and each template's `## When to use` first line.

- `run <name>` — Invoke the `pipeline-templates` skill in RUN mode. Resolve the template (user-dir first, then bundled). Hand the template's stages to the `handoff` skill in PIPELINE mode at step 2 (decompose / route already determined by the template). Follow the PIPELINE protocol from step 3 (BRIEF) through step 7 (synthesize). If a stage's role is `evaluator`, dispatch via `/evaluator-library run <domain> <artifact>` to enforce anti-self-grade.

- `run <name> --dry-run` — Same as `run`, but at step 4 (surface pipeline plan to user), STOP. Print the rendered plan and exit. No Agent dispatches.

- `save <name>` — Invoke the `pipeline-templates` skill in SAVE mode. Capture the just-completed pipeline shape (stages, decomposition axis, synthesis approach, failure criteria) and write it to `.claude/pipelines/<name>.md`. If the file already exists, ask the user before overwriting.

- (no recognized sub-command) — Default: invoke the `handoff` skill in **PIPELINE mode** for an ad-hoc pipeline. Follow the skill's PIPELINE procedure:
  1. Confirm the task is actually pipeline-shaped. If a single fast pass would do, abort.
  2. Decompose along concern / module / stage.
  3. Route each subtask (parallel / sequential / background).
  4. Surface the pipeline plan to the user before dispatching.
  4.5. If the next stage has a Generator, negotiate the sprint contract with a separate evaluator subagent first. Generator never gets dispatched against an un-vetted contract.
  5. For each subtask, call BRIEF mode to render a ≤30-line task description.
  6. Dispatch subagents via the Agent tool. Enforce anti-self-grade: evaluators are SEPARATE subagents with fresh context, given the contract + artifact only — never the generator's transcript.
  7. Synthesize results — explicit synthesis act, not concatenation.
  8. Offer to save the pipeline shape via `/pipeline save <name>` (Tier 2 closes this loop).

If `$ARGUMENT` is provided and is not a recognized sub-command, treat it as a hint about the pipeline's nature (e.g., "audit", "research", "refactor") — use it to bias the decomposition axis. Otherwise infer from the prompt.
