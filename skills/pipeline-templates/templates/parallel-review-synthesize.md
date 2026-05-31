# Pipeline: parallel-review-synthesize

## When to use
A single artifact (diff, PR, document, design) needs review from multiple independent perspectives, then a unified summary. Lighter weight than `audit-then-fix` (no fix stage). Good for: PR review with security + performance + code-quality angles, design review with engineering + product + accessibility angles, document review with clarity + accuracy + brand-voice angles.

## Decomposition axis
concern (parallel reviewer dispatches by domain, then a single synthesis)

## Stages

1. **parallel-review** (parallel)
   - Subagent role: evaluator (one per domain, dispatched via `evaluator-library run <domain> <artifact>`)
   - Inputs: the artifact path + the chosen domains. Domains MUST be one of the 6 bundled evaluator-library domains: `code-quality`, `ui-design`, `prose`, `security`, `performance`, `accessibility`. Defaults: `code-quality, security, performance` for code diffs; `prose` for written content (single-domain — the prose rubric already scores 4 axes: clarity / accuracy / brevity / hook); `ui-design, accessibility` for UI work.
   - Expected output: one `.claude/eval-reports/<domain>-<ts>.md` per domain
   - Forbidden: each evaluator runs in fresh context — no shared transcript, no peeking at peer reviewers' outputs. Never pass a rubric AXIS (clarity, accuracy, hook, brevity, etc.) as a domain — axes belong inside a rubric, not as dispatch keys.

2. **synthesize** (sequential)
   - Subagent role: synthesizer (main thread or dedicated subagent)
   - Inputs: all reviewer reports from stage 1
   - Expected output: `.claude/reviews/<artifact-slug>-unified.md` — merged findings with a shared severity scale (critical/high/medium/low), conflicts surfaced explicitly (e.g., "security reviewer wants X, performance reviewer wants not-X — orchestrator decides")
   - Sprint contract: synthesizer may NOT silently drop a reviewer's findings; conflicts must be named

## Synthesis
The stage 2 output IS the synthesis. Orchestrator surfaces it to the user with the per-domain reports linked for drilldown.

## Failure / abort criteria
- Any stage 1 evaluator returns VERDICT: NEEDS_WORK with a critical-severity finding → flag in the unified report (don't suppress)
- Stage 2 synthesizer drops a reviewer's findings → halt, redo synthesis with explicit "do not drop" instruction
- All evaluators return PASS → still produce the unified report; PASS is information too
