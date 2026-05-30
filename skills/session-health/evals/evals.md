# EVAL DEFINITION: session-health skill v0.7

**Skill:** `session-health` (Catalyst v0.7)
**Defined:** 2026-05-31 (pre-implementation — EDD)
**Merges:** `session-degradation-watch` (v0.6) + `failure-pattern-detector` (v0.5)
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for session-health v0.7. Evals defined before SKILL.md or hooks ship.

---

## Capability evals (12)

### Per-turn signals (UserPromptSubmit hook) — 7 evals

| ID | Name | What it proves |
|----|------|----------------|
| 0  | warns-at-effective-50pct | Hook fired against `transcript-warn-effective.jsonl` (~76525 tok, above 70000 WARN threshold) emits additionalContext with `/catalyst:handoff reground`. Fixture is deliberately below the old 120000-tok threshold, proving recalibration. |
| 1  | force-at-effective-70pct | Hook fired against `transcript-strong-effective.jsonl` (~109546 tok, above 98000 STRONG threshold) emits additionalContext with escalated urgency |
| 2  | repeated-tool-call-detected | Hook fired against a transcript with 3 identical Bash commands in last 5 turns flags the loop with a "try different approach" suggestion |
| 3  | stale-read-detected | Hook fired against a transcript where an Edit on file X happened more than 15 turns after the last Read of X emits a "re-Read X" suggestion |
| 4  | contradiction-flagged | Hook fired against a transcript where a stated decision contradicts a PROJECT_STATE.md entry surfaces the conflict explicitly |
| 5  | approaching-effective-window | Transcript at ~55% of a model's *effective* window triggers a per-turn degradation alert; old behavior (firing only at 75% of *advertised* window) is replaced — this eval proves the recalibrated threshold |
| 6  | reground-recipe | A degradation alert's recommended next step contains the literal `/catalyst:handoff reground` |

### Session-end patterns (Stop hook) — 5 evals

| ID | Name | What it proves |
|----|------|----------------|
| 7  | detects-repeated-tool-call | Mock transcript with same Bash command 4× in 5 turns → `repeated-tool-call` pattern detected and logged with a recovery recipe |
| 8  | detects-edit-mismatch | Transcript with 2 `old_string not found` errors in last 5 turns → `edit-mismatch` detected with recipe pointing at re-Reading the file |
| 9  | detects-stale-read-stop | Transcript: Read on file F at turn 1, Write to F at turn 10, Edit on F at turn 12 (no re-Read) → `stale-read` detected |
| 10 | detects-recovery-spiral | 3 consecutive re-Reads of previously-seen files → `recovery-spiral` detected and NOT fired below the threshold |
| 11 | no-false-positives-on-clean-session | Mock transcript with normal varied tool calls → no patterns detected, `.claude/failure-patterns.log` has no entry for that session |

---

## Regression evals (0)

*(No regression evals for initial v0.7 ship. Regression coverage will be added in v0.8 once the merged hook is stable. The `no-false-positives-on-clean-session` capability eval (ID 11) acts as the interim false-positive bar.)*

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (12) | pass@3 | ≥ 0.90 |
| Regression evals (0) | — | — |

---

## Recalibration: effective-window threshold

The old `session-degradation-watch` v0.6 thresholds were expressed as percentages of the *advertised* context window (e.g., warn at 60%, force at 85%). This was model-naïve: the actual usable window is typically 50–70% of the advertised limit before quality degrades.

`session-health` v0.7 recalibrates to fractions of the *effective* window:

| Level | Old trigger | New trigger | At advertised=200k |
|-------|-------------|-------------|-------------------|
| WARN  | 60% of advertised (120,000 tok) | 0.50 × effective window | 70,000 tok |
| STRONG | 85% of advertised (170,000 tok) | 0.70 × effective window | 98,000 tok |

Effective window is computed by the hook as: `effective = advertised_tokens × model_effective_fraction` where `model_effective_fraction` defaults to `0.70` (configurable). The char-count heuristic divides chars by 4 to estimate token usage.

Eval IDs 0, 1, and 5 specifically exercise this recalibrated logic.

---

## Recovery recipe requirement

Every per-turn alert and every session-end pattern detection MUST include a recovery recipe that:
1. Names a specific next step (not generic "try again")
2. References `/catalyst:handoff reground` for context-pressure alerts (degradation recovery)
3. References a concrete tool action or command for pattern-based detections

Eval ID 6 (`reground-recipe`) asserts the literal string `/catalyst:handoff reground` appears in any degradation alert.

---

## Graders

| Type | Used for |
|------|----------|
| Code | grep on hook stdout / `.claude/failure-patterns.log`, jq on `hookSpecificOutput.additionalContext`, file existence, string contains, literal OR-lists |

All leaf assertions bottom out in deterministic code checks (exact string match, file existence, jq parse). No Model grader is used — all assertions are code-gradeable.

---

## Anti-patterns caught by grading

- Hook fires on clean session (false positive)
- Suggestion is generic ("try again", "be careful") rather than actionable
- Context % calculation uses raw advertised window instead of effective window
- Multiple alerts surface simultaneously without prioritization (one alert per turn, most urgent first)
- Hook reads a transcript path that doesn't exist → crash instead of fail-open
- Patterns detected but no recovery recipe emitted
- Hook overwrites existing Stop or UserPromptSubmit entries instead of appending (composition regression)
- Recovery recipe mentions `/catalyst:handoff reground` only for non-degradation signals (recipe should be signal-specific)

---

## Coverage notes

- `instruction-fade` and `context-drowning` (from failure-pattern-detector v0.5 eval-debt) are carried forward as v0.8 eval-debt with stub entries `deferred-01`/`deferred-02` in evals.json. They require harder-to-fixture inputs and are not covered here.
- Live context-window monitoring against a real ongoing session is post-ship validation — fixtures simulate transcript shape only.
- Token-counting accuracy uses char-count heuristic by default (chars ÷ 4). Real tiktoken comparison is post-ship manual verification.
- PROJECT_STATE.md contradiction detection uses simple string match in v0.7; semantic detection deferred to v0.8+.
- Two-hook composition (UserPromptSubmit + Stop both installed) is a structural test deferred to T3.
