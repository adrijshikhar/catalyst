### Axes

| Axis | What it measures |
|------|------------------|
| `correctness` | Does the code do what its name / docstring / surrounding tests promise? Are edge cases handled (empty input, nulls, off-by-one)? |
| `readability` | Can a competent peer read this once and explain it? Are names accurate? Is control flow obvious? |
| `maintainability` | Is the change DRY without being premature-abstracted? Are dependencies and side effects explicit? Is the diff scoped to its stated purpose? |
| `test_coverage` | Do tests exercise the new/changed behavior? Are they meaningful (not just smoke)? Are failure modes tested, not just happy paths? |

### Score anchors (each axis 1-5)

- **5 — Exemplary.** Hard to improve. Use as reference for the team.
- **4 — Solid.** Production-ready. Minor nits only.
- **3 — Acceptable.** Ship-able with caveats. Specific issues to address.
- **2 — Needs work.** Don't ship without fixes.
- **1 — Reject.** Fundamental rework required.

### Critique guidance

For any axis scored ≤3, include a `Critique` block citing specific file:line locations and the concrete improvement. Generic feedback ("improve naming") is a critique failure.
