# EVAL DEFINITION: failure-pattern-detector skill v0.5

**Skill:** `failure-pattern-detector` (Catalyst v0.5)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** [docs/superpowers/specs/2026-05-24-tier-2-orchestration-extensions-design.md](../../../docs/superpowers/specs/2026-05-24-tier-2-orchestration-extensions-design.md)
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for failure-pattern-detector v0.5. Evals defined before SKILL.md or hook ships.

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | detects-repeated-tool-call | Mock transcript with same Bash command 4× in 5 turns → pattern detected and logged |
| 1 | detects-edit-mismatch | Transcript with 2 "old_string not found" errors in last 5 turns → pattern detected |
| 2 | detects-stale-read | Read on file F at turn 1, then Edit on F at turn 20 with another Write to F between → stale-read detected |
| 3 | detects-recovery-spiral | 3 consecutive turns starting with Read on already-seen files → recovery-spiral detected |
| 4 | no-false-positives-on-clean-session | Mock transcript with normal varied tool calls → no patterns detected |

**Coverage note:** This contract tests 4 of the 6 patterns from the SKILL.md specification as direct capability evals (`repeated-tool-call`, `edit-mismatch`, `stale-read`, `recovery-spiral`). The remaining 2 patterns (`instruction-fade`, `context-drowning`) are implemented in the hook (Task 5) but not yet under capability eval coverage — they require harder-to-fixture inputs (user-message replay and >10KB tool outputs respectively). Treat them as v0.6 eval-debt and document in `evals.log` when those evals land.

**Boundary discipline:** Evals 0 and 3 use two-fixture (positive + negative) prompts to guard the count thresholds (`repeated_tool_call_count=3`, `recovery_spiral_count=3`). Off-by-one errors in threshold reads will fail one of the two halves.

## Regression evals (1)

| ID | Name | What it protects |
|----|------|------------------|
| 5 | composes-with-tier-1-stop-hook | With Tier 1's Stop-commit-backstop.sh installed, installing failure-pattern-detect's Stop hook produces 2 Stop entries in settings.json — both compose, neither overwrites the other |

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
| Code | grep on failure-patterns.log content, jq on settings.json shape, file existence |
| Model | Quality of recovery recipe text (does it tell the user the next concrete step?) |

---

## Anti-patterns caught by grading

- Patterns detected but no recovery recipe emitted
- False positive on clean session (must be silent when nothing is wrong)
- Hook overwrites Tier 1 Stop entry instead of appending
- Detector reads non-transcript files (must scan transcript only)
- Recovery recipe is generic ("try again") rather than specific
