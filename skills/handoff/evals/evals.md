# EVAL DEFINITION: handoff skill v0.3

**Skill:** `handoff` (Catalyst v0.3)
**Defined:** 2026-05-24 (pre-implementation — eval-driven development)
**Spec:** `docs/superpowers/specs/2026-05-24-handoff-v0.3-feature-keying-design.md`
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for v0.3 before any SKILL.md change ships. Evals defined before implementation per EDD.

**Brief format:** All briefs are typed JSON validated against `skills/handoff/brief.schema.json`.
The legacy `.md` format was dropped pre-1.0. Tier-2 briefs are stored at `<store>/<key>.json`;
tier-3 (no-git fallback) uses `<store>/HANDOFF.json`. READ renders via `python3 scripts/handoff-render.py <key>`.

---

## Capability evals (17)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | write-tier-2-branch | Tier-2 resolution writes to `<store>/feat-jwt-expiry.json` (typed JSON, validated by `handoff-validate.py`), resume prompt in state + render output, feature-keyed narrative entry |
| 1 | write-tier-3-legacy-fallback | No-git fallback writes to `<store>/HANDOFF.json` (typed JSON, tier-3 key); backwards compatible |
| 2 | read-multi-brief | Multiple `.json` briefs present → skill surfaces all, defaults to branch match, never silently picks |
| 3 | read-legacy-fallback | Single-slot `HANDOFF.json` brief is consumed cleanly via `handoff-render.py --file` |
| 4 | recover-degraded | RECOVER overwrites `<key>.json` (passes validate gate), does NOT prepend to narrative; resume via render output |
| 5 | brief-subagent-mode | BRIEF produces ≤30 lines inline, no PROJECT_STATE.md inlined, no `.json` disk writes |
| 6 | pipeline-parallel | Two-concern task → one parallel stage + one synthesis stage |
| 7 | pipeline-sequential | research → plan → implement, structured inter-stage references, no inlined prior output |
| 8 | pipeline-synthesis-discipline | Parallel reviewers' findings merged into one report, unified severity scale |
| 9 | pipeline-abort-trivial | Trivial task → zero subagents, no pipeline preamble |
| 10 | pipeline-anti-self-grade | Generator and evaluator are SEPARATE subagents; evaluator gets contract + artifact only (no generator transcript) |
| 11 | pipeline-gan-loop | GAN-inspired iteration loop with bounded iterations + scoring threshold + stall surfacing |
| 13 | fresh-session-resumes-from-brief | Real-world dogfood: subagent reads `catalyst-dogfood-build.json` via `handoff-render.py`, quotes the next acceptance check, surfaces locked decisions + a rejected path, and lists the dogfood plan steps in order. Anti-context-bleed check: PROJECT_STATE.md is NOT auto-read. |
| 14 | split-proposes-and-confirms | SPLIT mode proposes ≥2 named threads from `split-two-thread-session.jsonl` and explicitly states it will NOT write brief files until confirmed; model-grade asserts proposal names feat-jwt-expiry + feat-rate-limit and declares write-freeze |
| 15 | split-writes-self-contained | After confirm, `feat-jwt-expiry.json` + `feat-rate-limit.json` both exist, each passes `handoff-validate.py` exit-0, each carries its own `next_acceptance_check`; shared decisions are copied into each brief's `state.decisions` and shared files into `files_read_first` — no `shared_context` field (schema-valid) |
| 16 | split-one-fork-narrative | Exactly ONE combined entry is prepended to `.claude/PROJECT_STATE.md` naming both `feat-jwt-expiry` and `feat-rate-limit`; first line of file remains `# Project state` |
| 17 | split-resume-isolation | `handoff-render.py feat-rate-limit` renders a complete, self-sufficient brief without requiring `feat-jwt-expiry.json` to be present (model-grade: brief is independently resumable) |
| — | typed-brief-validates | A WRITE-produced `<key>.json` passes `python3 scripts/handoff-validate.py <key>.json` exit-0 (required fields incl. worktree provenance). Asserted inline in evals 0, 1, 4. |

## Regression evals (0)

None. The former `regression-v0.2-legacy-mode` eval was removed in the typed-brief migration: legacy markdown briefs are **dropped pre-1.0** (no external users), so there is no legacy `.md` behavior left to guard. Briefs are typed JSON (`<store>/<key>.json`); the single-slot fallback is `HANDOFF.json`, covered by capability eval 3.

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (17) | pass@3 | ≥ 0.90 |
| All combined | pass@1 | ≥ 0.75 |

pass@3 = at least one of three independent dispatches satisfies all assertions for the eval. pass^3 = all three runs satisfy all assertions.

---

## Graders

| Type | Used for | Example |
|------|----------|---------|
| Code (deterministic) | File existence, path checks, line counts, regex matches, byte-for-byte equality, Agent tool invocation counts, path-overlap analysis | "Brief was written to `.claude/handoffs/feat-jwt-expiry.json` and `handoff-validate.py` exits 0" |
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

- Brief written to `<store>/HANDOFF.json` when a feature key was resolvable → `write-tier-2-branch` catches via path assertion
- Brief written as `.md` instead of validated `.json` → `write-tier-2-branch` and `write-tier-3-legacy-fallback` catch via `handoff-validate.py` exit-0 assertion
- BRIEF mode inlining PROJECT_STATE.md → `brief-subagent-mode` catches via substring check
- PIPELINE mode running for a trivial task → `pipeline-abort-trivial` catches via Agent invocation count = 0
- READ silently choosing a brief without surfacing alternatives → `read-multi-brief` catches via chat-response assertion
- RECOVER mutating PROJECT_STATE.md → `recover-degraded` catches via byte-for-byte equality
- RECOVER not re-validating the reconstructed brief → `recover-degraded` catches via `handoff-validate.py` exit-0 assertion
- Synthesis-by-concatenation in pipelines → `pipeline-synthesis-discipline` catches via LLM-as-judge
- Generator self-grading → `pipeline-anti-self-grade` catches by verifying separate Agent invocations
- GAN loop running on binary-pass-fail task → not directly tested in v0.3; relies on PIPELINE's "abort on trivial" heuristic
- Fresh session auto-reading PROJECT_STATE.md when brief says "do NOT load by default" → `fresh-session-resumes-from-brief` (id 13) catches via file-absence assertion
- SPLIT writing briefs before user confirms thread proposal → `split-proposes-and-confirms` (id 14) catches via file-absence assertion pre-confirm
- SPLIT producing briefs that omit `next_acceptance_check`, or fail to copy shared decisions into `state.decisions` / shared files into `files_read_first` → `split-writes-self-contained` (id 15) catches via `handoff-validate.py` exit-0 + contains checks; also catches any brief that adds a forbidden `shared_context` top-level key (schema: `additionalProperties: false`)
- SPLIT writing multiple PROJECT_STATE.md entries instead of one combined fork entry → `split-one-fork-narrative` (id 16) catches via line-count + header assertion
- SPLIT brief for thread B depending on thread A being present to be readable → `split-resume-isolation` (id 17) catches via model-grade self-sufficiency check

---

## Future: `claude -p` headless integration eval (deferred to v0.7)

Eval id 13 is a subagent-based test — fast and cheap but uses the parent session's tool config. A higher-fidelity follow-up uses `claude -p` headless to run a real CLI session with real hooks, capture the response, and grade it. Sketched in `scripts/eval-handoff-resume.sh` (NOT shipped in v0.4 — deferred to v0.7+ as part of the Tier 5+ `dogfood-eval` skill or as a `.github/workflows/handoff-resume-eval.yml` CI job once CI has access to an `ANTHROPIC_API_KEY` secret).

See `docs/ROADMAP.md` "Future-work index" for the formal entry.

---

## Run log

Each handoff-touching commit appends a one-line entry to `evals.log` in this dir with date, commit SHA, and pass rate.
