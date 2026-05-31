# EVAL DEFINITION: brain-bridge skill v0.6

**Skill:** `brain-bridge` (Catalyst v0.6)
**Defined:** 2026-05-25 (pre-implementation — EDD)
**Spec:** `docs/superpowers/specs/2026-05-24-tier-3-knowledge-integration-design.md`
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for brain-bridge v0.6. Evals defined before SKILL.md or adapter shims ship.

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | adapter-normalizes-output | Each of 3 adapters (gbrain, brain, codebase-memory-mcp) converts its raw output into the normalized pointer JSON shape (results array with type/path/lines/relevance OR type/id/title) |
| 2 | token-budget-respected | When configured `query_token_budget: 100`, oversized output is truncated; lowest-relevance pointers dropped first |
| 3 | relevance-threshold-filters | Pointers below `relevance_threshold` (default 0.5) are excluded from the normalized output |
| 4 | backend-missing-fail-open | Adapter invoked for an unconfigured/missing backend exits non-zero with a clean error AND prints empty results JSON (caller can render brief without `## Brain pointers` section) |
| 5 | pipeline-brief-integration | When the SKILL.md `## Brain pointers` template is rendered into a handoff PIPELINE BRIEF, the section appears between `## Files to read first` and `## Files to NOT load by default`, contains pointers only (NOT content) |

## Regression evals (2)

| ID | Name | What it protects |
|----|------|------------------|
| 1 | brief-adds-pointers-not-content | A rendered BRIEF that includes brain results contains pointers (file:line, decision IDs, doc tags) but NEVER the actual file content. Anti-bleed rule preserved. Catches future regressions where someone inlines content into the brief. |
| 6 | brief-preserves-all-pointers | Every adapter-emitted file:line pointer must appear in the rendered BRIEF — no pointer silently dropped. Verified via `scripts/check-fidelity.py` (load-bearing invariant preservation). Complements eval 1: eval 1 guards against *adding* content, eval 6 guards against *dropping* pointers. |

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
| Code | jq on normalized JSON shape, grep for content-leak in brief, file existence |
| Model | Quality of the rendered brief integration (pointers appear in correct section, no inlining) |

---

## Anti-patterns caught by grading

- Adapter returns un-normalized backend-specific shape (defeats pointer contract)
- Brief inlines file content instead of file:line pointer (anti-bleed violation)
- Backend-missing crash propagates to brief render (must fail-open)
- Relevance threshold ignored (low-quality pointers leak into brief)
- Token budget exceeded silently (caller has no way to know brief was truncated)

## Coverage notes

- Live MCP server interaction is NOT exercised (eval uses fixtures simulating raw backend output). Real-server smoke test is post-Task-6 manual verification.
- Adapter authoring (user adds a 4th adapter) is out of scope for v0.6 evals; that's v0.7+ work per spec.
