# EVAL DEFINITION: hook-builder skill v0.4

**Skill:** `hook-builder` (Catalyst v0.4)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** [docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md](../../../docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md)

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | install-single-precompact | `/hook-builder install PreCompact` adds entry to settings.json + copies script to .claude/hooks/ |
| 1 | install-all-four | `/hook-builder install --all` adds all 4 lifecycle hooks idempotently |
| 2 | uninstall-removes-cleanly | `/hook-builder uninstall PreCompact` removes settings.json entry + deletes hook script |
| 3 | new-event-scaffold | `/hook-builder new PostToolUse my-custom-hook` produces a valid hook script template at hooks/PostToolUse-my-custom-hook.sh |
| 4 | lint-catches-bad-matcher | `/hook-builder lint <path>` flags a hook with matcher ".*" as too broad |

## Regression evals (0)

This skill primarily orchestrates other components. Regression coverage comes from the integration test in Task 8.

---

## Thresholds

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (5) | pass@3 | ≥ 0.90 |

---

## Graders

| Type | Used for |
|------|----------|
| Code | settings.json shape + content, file existence, hook script syntax (bash -n) |
| Model | Quality of scaffolded hook template (does it follow the contract?) |
