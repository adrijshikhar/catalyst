# EVAL DEFINITION: handoff skill v0.3

**Skill:** `handoff` (Catalyst v0.3)
**Defined:** 2026-05-24 (pre-implementation — eval-driven development)
**Spec:** `docs/superpowers/specs/2026-05-24-handoff-v0.3-feature-keying-design.md`
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for v0.3 before any SKILL.md change ships. Evals defined before implementation per EDD.

---

## Capability evals (13)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | write-tier-2-branch | Tier-2 resolution writes to `.claude/handoffs/<branch>.md`, with Resume prompt and feature-keyed narrative entry |
| 1 | write-tier-3-legacy-fallback | No-git fallback writes to legacy `.claude/HANDOFF.md` (backwards compatible) |
| 2 | read-multi-brief | Multiple briefs present → skill surfaces all, defaults to branch match, never silently picks |
| 3 | read-legacy-fallback | Legacy v0.2-shaped brief is consumed cleanly (no Resume prompt section is fine) |
| 4 | recover-degraded | RECOVER overwrites the resolved key's brief but does NOT prepend to narrative |
| 5 | brief-subagent-mode | BRIEF produces ≤30 lines inline, no PROJECT_STATE.md inlined, no disk writes |
| 6 | pipeline-parallel | Two-concern task → one parallel stage + one synthesis stage |
| 7 | pipeline-sequential | research → plan → implement, structured inter-stage references, no inlined prior output |
| 8 | pipeline-synthesis-discipline | Parallel reviewers' findings merged into one report, unified severity scale |
| 9 | pipeline-abort-trivial | Trivial task → zero subagents, no pipeline preamble |
| 10 | pipeline-anti-self-grade | Generator and evaluator are SEPARATE subagents; evaluator gets contract + artifact only (no generator transcript) |
| 11 | pipeline-gan-loop | GAN-inspired iteration loop with bounded iterations + scoring threshold + stall surfacing |
| 13 | fresh-session-resumes-from-brief | Real-world dogfood: subagent given the catalyst-dogfood-build brief Reads it first, quotes the next acceptance check, surfaces locked decisions + a rejected path, and lists the dogfood plan steps in order. Anti-context-bleed check: PROJECT_STATE.md is NOT auto-read. |

## Regression evals (1)

| ID | Name | Baseline |
|----|------|----------|
| 12 | regression-v0.2-legacy-mode | v0.2 SKILL.md snapshot in `skills/handoff-workspace/v0.2-snapshot/` — v0.2 must still produce a working brief at `.claude/HANDOFF.md` in legacy mode |

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (13) | pass@3 | ≥ 0.90 |
| Regression eval (1) | pass^3 | = 1.00 (release-critical) |
| All combined | pass@1 | ≥ 0.75 |

pass@3 = at least one of three independent dispatches satisfies all assertions for the eval. pass^3 = all three runs satisfy all assertions.

---

## Graders

| Type | Used for | Example |
|------|----------|---------|
| Code (deterministic) | File existence, path checks, line counts, regex matches, byte-for-byte equality, Agent tool invocation counts, path-overlap analysis | "Brief was written to `.claude/handoffs/feat-jwt-expiry.md`" |
| Model (LLM-as-judge) | Synthesis quality, duplicate-merging, unified severity scales, brief filtering correctness, "is this one plan or two stapled reports?", evaluator-was-separate-subagent | "combined-plan.md is ONE unified plan, not two stapled reports" |
| Human (manual) | Brief-schema round-trip — verify a BRIEF-mode brief can be promoted to a WRITE brief without field renaming (one-time per release) | n/a — interactive |

---

## Run mechanics

Each eval dispatches a subagent via the Agent tool. The subagent's prompt loads the appropriate SKILL.md (v0.3 for capability, v0.2-snapshot for regression), then executes the eval's test prompt against a freshly-created working dir with the eval's fixture files copied in.

Outputs land at:

```
catalyst/                       (workspace, gitignored)
└── skills/
    └── handoff-workspace/
        └── iteration-<N>/
            └── eval-<id>-<name>/
                └── run-<k>/
                    ├── outputs/        (subagent's writes)
                    ├── response.md     (chat transcript — for pipeline graders)
                    ├── grading.json    (assertion results)
                    └── timing.json     (tokens + ms)
```

`grade.py` (in the workspace) runs deterministic code graders and dispatches a model-grader subagent for model-grade assertions. Results aggregate via `python -m scripts.aggregate_benchmark` (the same script handoff v0.2 used).

---

## Anti-patterns caught by grading

- Brief written to `.claude/HANDOFF.md` when a feature key was resolvable → `write-tier-2-branch` catches via path assertion
- BRIEF mode inlining PROJECT_STATE.md → `brief-subagent-mode` catches via substring check
- PIPELINE mode running for a trivial task → `pipeline-abort-trivial` catches via Agent invocation count = 0
- READ silently choosing a brief without surfacing alternatives → `read-multi-brief` catches via chat-response assertion
- RECOVER mutating PROJECT_STATE.md → `recover-degraded` catches via byte-for-byte equality
- Synthesis-by-concatenation in pipelines → `pipeline-synthesis-discipline` catches via LLM-as-judge
- Generator self-grading → `pipeline-anti-self-grade` catches by verifying separate Agent invocations
- GAN loop running on binary-pass-fail task → not directly tested in v0.3; relies on PIPELINE's "abort on trivial" heuristic
- Fresh session auto-reading PROJECT_STATE.md when brief says "do NOT load by default" → `fresh-session-resumes-from-brief` (id 13) catches via file-absence assertion

---

## Future: `claude -p` headless integration eval (deferred to v0.7)

Eval id 13 is a subagent-based test — fast and cheap but uses the parent session's tool config. A higher-fidelity follow-up uses `claude -p` headless to run a real CLI session with real hooks, capture the response, and grade it. Sketched in `scripts/eval-handoff-resume.sh` (NOT shipped in v0.4 — deferred to v0.7+ as part of the Tier 5+ `dogfood-eval` skill or as a `.github/workflows/handoff-resume-eval.yml` CI job once CI has access to an `ANTHROPIC_API_KEY` secret).

See `docs/ROADMAP.md` "Future-work index" for the formal entry.

---

## Run log

Each handoff-touching commit appends a one-line entry to `evals.log` in this dir with date, commit SHA, and pass rate.
