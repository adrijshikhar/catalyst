# EVAL DEFINITION: evaluator-library skill v0.5

**Skill:** `evaluator-library` (Catalyst v0.5)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** [docs/superpowers/specs/2026-05-24-tier-2-orchestration-extensions-design.md](../../../docs/superpowers/specs/2026-05-24-tier-2-orchestration-extensions-design.md)
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for evaluator-library v0.5. Evals defined before SKILL.md or dispatcher rubric content ships.

---

## Capability evals (6)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | evaluator-dispatches-fresh-context | dispatch-evaluator.sh brief output contains explicit "Forbidden: reading the generator's transcript" — anti-self-grade rule is in every dispatch |
| 1 | evaluator-returns-structured-report | A run against `code-quality` rubric on a sample diff produces an eval-report.md with per-axis scores + VERDICT line |
| 2 | evaluator-respects-readonly | Brief includes "Modifying any file" in the Forbidden list — evaluator subagent treats artifact as read-only |
| 3 | evaluator-rubric-domain-distinct | Running `code-quality` and `ui-design` against the same artifact produces meaningfully different rubric content in the dispatched brief |
| 4 | evaluator-threshold-configurable | Setting `.claude/evaluator-library.json` pass_threshold to 5 causes the brief to state "All axes >= 5" |
| 6 | user-rubric-overrides-bundled | User rubric at `.claude/evaluator-library/evaluators/<domain>.md` takes precedence over plugin-bundled rubric — verified via marker string |

## Regression evals (1)

| ID | Name | What it protects |
|----|------|------------------|
| 5 | regression-dispatcher-stateless-anti-self-grade | Calling the dispatcher 3 times in sequence produces 3 independently-correct briefs (anti-self-grade rule never decays, no state leaks across calls) |

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (6) | pass@3 | ≥ 0.90 |
| Regression eval (1) | pass^3 | = 1.00 |

---

## Graders

| Type | Used for |
|------|----------|
| Code | grep / jq match on brief content, file existence, exit codes |
| Model | Quality of rubric anchor descriptions in produced briefs (do they discriminate between scores?) |

---

## Anti-patterns caught by grading

- Brief omits the "Forbidden" section (lets evaluator drift)
- Same rubric content for two different domains (rubric collapse)
- Pass threshold ignored when config overrides it
- Brief includes the artifact's full content (instead of just a reference)
- Brief references a transcript path or session log (anti-self-grade violation)
