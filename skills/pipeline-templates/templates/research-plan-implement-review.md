# Pipeline: research-plan-implement-review

## When to use
Multi-day or multi-week feature work from a fuzzy ask to a reviewed PR. The canonical "real software shipping" loop. Good for: new feature, non-trivial refactor, integration of a new library, redesign of a subsystem.

## Decomposition axis
stage (research → plan → contract → implement → review — strictly sequential)

## Stages

1. **research** (sequential)
   - Subagent role: researcher
   - Inputs: the user's ask + the repo + relevant docs / specs
   - Expected output: `.claude/research/<feature-slug>.md` — domain context, prior art, options analysis with tradeoffs, recommended approach
   - Forbidden: writing any code; this stage is strictly read-only investigation

2. **plan** (sequential)
   - Subagent role: planner (via `superpowers:writing-plans`)
   - Inputs: the research artifact from stage 1 + the user's ask
   - Expected output: `docs/superpowers/plans/<date>-<feature-slug>.md` — task-by-task implementation plan with file paths, code samples, test cases, commit boundaries
   - Sprint contract: "Plan must mirror the structure of existing plans in `docs/superpowers/plans/`. Each task is bite-sized (2-5 minute steps). EDD ordering enforced."

3. **contract-handshake** (sequential, anti-self-grade)
   - Two subagents: contract-author (generator-side) and contract-reviewer (evaluator-side, fresh context)
   - Inputs: the plan from stage 2
   - Expected output: `.claude/contracts/<feature-slug>.md` — explicit acceptance criteria the evaluator will check, signed off by both sides BEFORE generator starts
   - Forbidden: contract-reviewer never sees contract-author's reasoning, only the plan + draft contract

4. **implement** (sequential, can be batched per task)
   - Subagent role: generator (via `superpowers:subagent-driven-development`)
   - Inputs: the plan + the contract
   - Expected output: a feature branch with task-by-task commits matching the plan
   - Sprint contract: the contract from stage 3 IS the acceptance bar — generator may NOT amend it mid-stream

5. **review** (sequential, anti-self-grade)
   - Subagent role: evaluator (via `evaluator-library run code-quality <diff>`)
   - Inputs: the diff from stage 4 + the contract
   - Expected output: `.claude/reviews/<feature-slug>.md` — code-quality rubric scores + PASS/NEEDS_WORK against the contract
   - Forbidden: reading stage 4 subagent's transcript

## Synthesis
Orchestrator collects the review verdict. If PASS, opens the PR with the contract + review attached. If NEEDS_WORK, loops back to stage 4 with the specific critique — does NOT discard the contract.

## Failure / abort criteria
- Stage 2 plan diverges from research recommendation without justification → halt, surface
- Stage 3 contract-handshake fails to converge after 2 rounds → halt, escalate to user
- Stage 5 review fails 3 times on the same contract → contract was probably wrong; re-open stage 3
