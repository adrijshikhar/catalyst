## Task
Evaluate the artifact at `sample-diff.patch` against the `code-quality` rubric.

## Rubric
### Axes

| Axis | What it measures |
|------|------------------|
| `correctness` | Does the code do what its name promises? Are edge cases handled? |
| `readability` | Can a competent peer read this once and explain it? |
| `maintainability` | Is the change DRY without premature abstraction? Are dependencies and side effects explicit? |
| `test_coverage` | Do tests exercise the new behavior? Are they meaningful? Are failure modes tested? |

### Score anchors (each axis 1-5)
- 5 — Exemplary. 4 — Solid. 3 — Acceptable. 2 — Needs work. 1 — Reject.

## Pass threshold
All axes >= 4.

## Inputs (read-only — do NOT modify)
- artifact: sample-diff.patch

## Forbidden
- Reading the generator's transcript (anti-self-grade rule)
- Modifying any file (you have Read-only access)
- Inventing axes not in the rubric
- Asking the user clarifying questions

## Output
Write a structured report at `eval-report.md` with:
- One section per axis: score (1-5) + one-sentence rationale (axis name on its own line, followed by score)
- Overall verdict line: `VERDICT: PASS` or `VERDICT: NEEDS_WORK`
- For each failing axis, a "Critique" subsection with specific actionable feedback
