# EVAL DEFINITION: pipeline-templates skill v0.5

**Skill:** `pipeline-templates` (Catalyst v0.5)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** `docs/superpowers/specs/2026-05-24-tier-2-orchestration-extensions-design.md`
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for pipeline-templates v0.5. Evals defined before SKILL.md or template runtime ships.

---

## Capability evals (5)


| ID | Name | What it proves |
|----|------|----------------|
| 0 | list-shows-bundled-templates | `/pipeline list` includes the 3 bundled templates AND distinguishes them from user-saved templates (catches bundled-only regression) |
| 1 | dry-run-prints-plan-without-dispatching | `/pipeline run audit-then-fix --dry-run` outputs the plan; verified by snapshotting `.claude/eval-reports/` and `.claude/audits/` before/after — neither changes |
| 2 | run-bundled-audit-then-fix-renders-stage-plan | `/pipeline run audit-then-fix` produces a stage-plan rendering that lists all 4 stages in PIPELINE-mode order; also renders a 5-stage template (research-plan-implement-review) without truncation (covers stage count > 3 anti-pattern) |
| 3 | save-writes-file-and-list-shows-it | `/pipeline save <name>` writes a markdown file under `.claude/pipelines/` and a subsequent list call shows it labeled as user/saved (NOTE: scaffolded prompt — full save-from-actual-pipeline-run is post-Task-7 integration coverage) |
| 4 | user-template-overrides-bundled | If `.claude/pipelines/audit-then-fix.md` exists, `/pipeline run audit-then-fix` uses the user version, not the bundled one (CUSTOM-USER-TEMPLATE marker test) |

## Regression evals (2)

| ID | Name | What it protects |
|----|------|------------------|
| 5 | template-with-evaluator-stage-dispatches-via-evaluator-library | A template stage of type "evaluator" with `domain: code-quality` references the evaluator-library dispatch path; domain must be appropriate for audit-then-fix (code-quality/security/performance, not ui-design/prose/accessibility) |
| 6 | template-domain-must-exist-in-bundled-set | Every bundled template's `evaluator-library run <X>` and `default domains` references must name one of the 6 bundled domains (code-quality, ui-design, prose, security, performance, accessibility). Rubric AXES (clarity, accuracy, hook, brevity, correctness, readability, maintainability, test_coverage) referenced as if they were domains are a critique failure. Catches the parallel-review-synthesize bug where the template defaulted to `clarity, accuracy, hook for prose` (axes), which would dispatch to non-existent `clarity.md` / `accuracy.md` / `hook.md` rubrics. |

**Coverage notes:**
- Live Agent dispatch is NOT exercised by these capability evals. Eval 2 explicitly produces the BRIEF that would be dispatched, not the dispatch itself, because end-to-end live dispatch requires a Tier 4 multi-agent test harness. Live dispatch coverage is post-Task-7 integration work (treat as v0.6 eval-debt).
- Save-from-actual-pipeline-run is scaffolded in eval 3 (the pipeline shape is described in the prompt rather than captured from a real run). Full save-from-real-run is also post-Task-7 integration coverage.
- Save overwrite-protection (spec says `/pipeline save <name>` must ask before overwriting an existing template) has no direct eval — covered by Task 7 manual verification.

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (5) | pass@3 | ≥ 0.90 |
| Regression eval (1) | pass^3 | = 1.00 |

---

## Graders

| Type | Used for |
|------|----------|
| Code | grep on output, file existence, jq on metadata blocks |
| Model | Quality of the rendered stage plan (does it have correct role + inputs + expected output per stage?) |

---

## Anti-patterns caught by grading

- Dry-run actually dispatches agents (defeats `--dry-run`)
- User template silently ignored when bundled exists
- Template format breaks when stage count > 5 (must support N stages)
- Templates that reference evaluator-library by-pass the dispatcher (anti-self-grade risk)
- `save` overwrites bundled templates (must write only to user dir)
