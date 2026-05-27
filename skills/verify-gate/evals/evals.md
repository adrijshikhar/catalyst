# EVAL DEFINITION: verify-gate skill v0.4

**Skill:** `verify-gate` (Catalyst v0.4)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** [docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md](../../../docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md)
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for verify-gate v0.4. Evals defined before SKILL.md or hook ships.

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | hook-blocks-unverified-claim-write | PreToolUse hook returns deny when agent writes test-results.json without prior Read on test-output.log |
| 1 | hook-allows-after-evidence-read | Same scenario but with prior Read on test-output.log present in transcript → hook returns allow |
| 2 | hook-respects-freshness-window | Read occurred >10min before write → hook returns deny ("stale evidence") |
| 3 | hook-respects-config-overrides | Project-level .claude/verify-gate.json adds a custom claim rule → hook honors it |
| 4 | install-command-wires-settings | /verify-gate install copies hook to .claude/hooks/ AND appends correct entry to .claude/settings.json |

## Regression evals (1)

| ID | Name | What it protects |
|----|------|------------------|
| 5 | handoff-v03-evals-still-pass-with-verify-gate-installed | Run handoff v0.3 eval-0 (write-tier-2-branch) with verify-gate hook active → handoff still writes brief + state without false-positive block |

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
| Code | Hook exit code, output JSON shape, file existence, settings.json content match |
| Model | Reasoning quality of denial messages (does the message tell the agent what evidence to Read?) |

---

## Anti-patterns caught by grading

- Hook denies legitimate writes (false positive — would break user workflows)
- Hook allows claims without evidence (false negative — defeats the gate)
- Hook errors on missing config and blocks the user (must fail-open on infra error)
- Install command corrupts existing settings.json (must merge, not replace)
- Stale evidence (Read >10min ago) silently allows write (must enforce freshness window)
