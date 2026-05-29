# EVAL DEFINITION: session-degradation-watch skill v0.6

**Skill:** `session-degradation-watch` (Catalyst v0.6)
**Defined:** 2026-05-25 (pre-implementation — EDD)
**Spec:** `docs/superpowers/specs/2026-05-24-tier-3-knowledge-integration-design.md`
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for session-degradation-watch v0.6. Evals defined before SKILL.md or hook ships.

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | warns-at-60-pct-context | Hook fired against a transcript estimated at 60% context emits additionalContext with a "consider handoff WRITE" suggestion (warn level) |
| 1 | force-at-85-pct | Hook fired against a transcript estimated at 85% context emits additionalContext with a strong "call handoff NOW" recommendation |
| 2 | repeated-tool-call-detected | Hook fired against a transcript with 3 identical Bash commands in last 5 turns emits additionalContext flagging the loop with a "try different approach" suggestion |
| 3 | stale-read-detected | Hook fired against a transcript where an Edit on file X happened more than 15 turns after the last Read of X emits a "re-Read X" suggestion |
| 4 | contradiction-flagged | Hook fired against a transcript where a stated decision contradicts a PROJECT_STATE.md entry surfaces the conflict explicitly |

## Regression evals (1)

| ID | Name | What it protects |
|----|------|------------------|
| 5 | no-noise-on-clean-session | Clean transcript (no signals) → hook emits NO additionalContext (false-positive bar). Catches over-eager alert regression. |

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (5) | pass@3 | ≥ 0.90 |
| Regression eval (1) | pass^3 | = 1.00 (no false positives in 3 consecutive clean-session runs) |

---

## Graders

| Type | Used for |
|------|----------|
| Code | grep on hook output JSON, jq on additionalContext field, line counts on log file |
| Model | Quality of the suggestion text (specific, actionable, names the next step) |

---

## Anti-patterns caught by grading

- Hook fires on clean session (false positive)
- Suggestion is generic ("try again", "be careful") instead of actionable ("call handoff WRITE", "re-Read X")
- Context % calculation is silently wrong (e.g., always reports 0% regardless of input)
- Multiple alerts surface simultaneously without prioritization (must pick one signal — most urgent)
- Hook reads transcript_path that doesn't exist → crash instead of fail-open

## Coverage notes

- Token-counting accuracy is not directly graded (uses approximate char-heuristic by default). Real tiktoken comparison is post-Task-6 manual verification.
- Live context-window monitoring (against real ongoing session) is post-ship validation — fixtures simulate the transcript shape only.
- PROJECT_STATE.md contradiction detection uses simple string match in v0.6; semantic contradiction detection deferred to v0.7+.
