# Pipeline: audit-then-fix

## When to use
A codebase or system audit followed by fixes for the highest-priority findings. Good for security passes, performance reviews, dependency cleanup sweeps, and similar "find issues then resolve them" workflows.

## Decomposition axis
concern (security + performance + correctness audit in parallel, then sequential fix + verify)

## Stages

1. **parallel-audit** (parallel)
   - Subagent role: auditor (3 separate dispatches, one per concern)
   - Inputs: repo root, scope hint (e.g., `src/api/`)
   - Expected output: `.claude/audits/security-findings.md`, `.claude/audits/performance-findings.md`, `.claude/audits/correctness-findings.md`
   - Each finding: title, file:line, severity (critical/high/medium/low), reproducer or evidence, proposed fix

2. **prioritize** (sequential)
   - Subagent role: orchestrator (NOT a subagent — main thread synthesizes)
   - Inputs: the 3 findings files from stage 1
   - Expected output: `.claude/audits/prioritized-findings.md` — top N items ordered by severity × confidence × blast radius, with explicit ordering rationale

3. **fix-top-n** (sequential)
   - Subagent role: generator
   - Inputs: `.claude/audits/prioritized-findings.md`, the target repo
   - Expected output: a series of focused commits, one per finding addressed, each referencing the finding ID
   - Sprint contract: "Fix findings 1..N from prioritized-findings.md. Each fix must include or update tests. No unrelated changes."

4. **verify-fixes** (sequential)
   - Subagent role: evaluator (via `evaluator-library run code-quality <diff>`)
   - Inputs: the diff produced by stage 3 + the original findings file
   - Expected output: `.claude/audits/verification-report.md` — per-finding PASS/NEEDS_WORK + axis scores from the code-quality rubric
   - Forbidden: reading stage 3 subagent's transcript (anti-self-grade)

## Synthesis
After stage 4, the orchestrator: (a) lists fixes that PASSED, (b) lists fixes that NEEDS_WORK and queues them for another round, (c) writes a final `audit-and-fix-report.md` summarizing the entire pipeline.

## Failure / abort criteria
- Any stage 1 auditor finds a critical severity issue → halt fixes, surface to user immediately (don't auto-fix critical bugs without human review)
- Stage 3 produces a commit that breaks the build → roll back, surface, halt
- Stage 4 evaluator returns NEEDS_WORK on more than 50% of fixes → halt, surface, ask user to inspect rubric / generator output
