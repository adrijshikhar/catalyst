# EVAL DEFINITION: handoff skill v0.3

**Skill:** `handoff` (Catalyst v0.3)
**Defined:** 2026-05-24 (pre-implementation — eval-driven development)
**Spec:** `projects/catalyst/specs/2026-05-24-handoff-v0.3-feature-keying-design.md` (private planning repo)
**Test prompts + assertions:** [evals.json](./evals.json)

Binding contract for v0.3 before any SKILL.md change ships. Evals defined before implementation per EDD.

**Brief format:** All briefs are typed JSON validated against `skills/handoff/brief.schema.json`.
The legacy `.md` format was dropped pre-1.0. Tier-2 briefs are stored at `<store>/<key>.json`;
tier-3 (no-git fallback) uses `<store>/HANDOFF.json`. READ renders via `python3 scripts/handoff-render.py <key>`.

---

## Capability evals (10)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | write-tier-2-branch | Tier-2 resolution writes to `<store>/feat-jwt-expiry.json` (typed JSON, validated by `handoff-validate.py`), resume prompt in state + render output, feature-keyed narrative entry |
| 1 | write-tier-3-legacy-fallback | No-git fallback writes to `<store>/HANDOFF.json` (typed JSON, tier-3 key); backwards compatible |
| 2 | read-multi-brief | Multiple `.json` briefs present → skill surfaces all, defaults to branch match, never silently picks |
| 3 | read-legacy-fallback | Single-slot `HANDOFF.json` brief is consumed cleanly via `handoff-render.py --file` |
| 4 | recover-degraded | RECOVER overwrites `<key>.json` (passes validate gate), does NOT prepend to narrative; resume via render output |
| 5 | brief-subagent-mode | BRIEF produces ≤30 lines inline, no PROJECT_STATE.md inlined, no `.json` disk writes |
| 13 | fresh-session-resumes-from-brief | Real-world dogfood: subagent reads `catalyst-dogfood-build.json` via `handoff-render.py`, quotes the next acceptance check, surfaces locked decisions + a rejected path, and lists the dogfood plan steps in order. Anti-context-bleed check: PROJECT_STATE.md is NOT auto-read. |
| 18 | read-drift-missing-file | READ surfaces `!! MISSING: <path>` for a `files_read_first` path that no longer exists (relative, resolved against `state.worktree.root`), and the agent acknowledges it (`ACK MISSING`) instead of resuming blind |
| 19 | read-drift-stale-brief | READ surfaces `!! STALE: brief written ~10d ago (…)` for a brief 10 days older than the injected `--now`; the agent acknowledges it (`ACK STALE`) with a git-diff step |
| 20 | read-drift-commits-since | READ shows `- Commits since brief written: N` from `state.head_sha` (real git at the repo root; sha = the #69 merge `82de465`); the agent acknowledges it (`ACK COMMITS`) and names `git log --oneline 82de465..HEAD` |
| — | typed-brief-validates | A WRITE-produced `<key>.json` passes `python3 scripts/handoff-validate.py <key>.json` exit-0 (required fields incl. worktree provenance). Asserted inline in evals 0, 1, 4. |

## Regression evals (1)

| ID | Name | What it proves |
|----|------|----------------|
| 21 | read-drift-clean-brief | A fresh, `head_sha`-less brief with no `files_read_first` renders with **no** `!! STALE` / `!! MISSING` line and the normal `## Resume prompt` scaffold (back-compat for pre-#69 briefs); the agent reports `DRIFT: clean` |

Historical note: the former `regression-v0.2-legacy-mode` eval was removed in the typed-brief migration: legacy markdown briefs are **dropped pre-1.0** (no external users), so there is no legacy `.md` behavior left to guard. Briefs are typed JSON (`<store>/<key>.json`); the single-slot fallback is `HANDOFF.json`, covered by capability eval 3.

---

## Drift-validation evals (ids 18–21) — added 2026-09-02, post-hoc for #69

> **2026-09-02 (v0.7.0 strip):** evals 6–11 (PIPELINE) and 14–17 (SPLIT) were retired with their modes; excerpts live in the private planning repo under `archived/handoff-pipeline-mode/` and `archived/handoff-split-mode/`. Ids are not renumbered.

#69 shipped the three READ-time drift checks (`!! MISSING`, `!! STALE`, `Commits since brief written`) with unit tests only (`tests/test_handoff_render.py` TestDrift*, `tests/test_handoff_validate.py` TestHeadShaField). These behavioral evals were added afterwards — an EDD-ordering exception, recorded here rather than hidden.

- Every assertion is grader-deterministic per `scripts/eval-grade.py` (`X exists` or quoted needles, all required). No negative assertions — the grader cannot express them.
- The transcript grader cannot tell tool output from agent output, so agent behavior is asserted through sentinels only the agent can author: `ACK MISSING` / `ACK STALE` / `ACK COMMITS` / `DRIFT: clean`. Raw `!! …` needles prove the renderer fired; sentinels prove the agent heeded it.
- Prompts reference the committed fixture path via `handoff-render.py --file <path> --now <ISO>`. `scripts/eval-run.py` runs prompts at the repo root and does not stage `files[]`, so the fixture must be reachable from there; the `files[]` mirror is kept for the subagent runner. `--now` makes the age deterministic (eval 19 → exactly `~10d`).
- Eval 20 requires a real catalyst git checkout at the working root (it counts `82de465..HEAD`); in a git-less scratch dir the renderer emits no commits line by design (fail-open) and the eval fails.
- Fixture worktree roots are placeholders (`/workspace/project`, `/workspace/catalyst`), so a `!! REPO MISMATCH` line appears on real machines; the evals ask for a drift *report*, not a resume, so it is acknowledged, not fatal. Positive file-existence is covered at unit level (`test_existing_relative_file_no_warning`) because a portable absolute root cannot be committed.
- Snapshot status: **none** — Lane B (`scripts/eval-run.py`) was deliberately not run on 2026-09-02; `eval-grade.py` reports `WARN handoff: no snapshot` and enforces nothing until a snapshot is seeded.

---

## Thresholds (release gate)

| Class | Metric | Threshold |
|-------|--------|-----------|
| Capability evals (10) | pass@3 | ≥ 0.90 |
| Regression evals (1) | pass^3 | = 1.00 |
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
                    ├── response.md     (chat transcript — for chat-response graders)
                    ├── grading.json    (assertion results)
                    └── timing.json     (tokens + ms)
```

`grade.py` (in the workspace) runs deterministic code graders and dispatches a model-grader subagent for model-grade assertions. Results aggregate via `python -m scripts.aggregate_benchmark` (the same script handoff v0.2 used).

---

## Anti-patterns caught by grading

- Brief written to `<store>/HANDOFF.json` when a feature key was resolvable → `write-tier-2-branch` catches via path assertion
- Brief written as `.md` instead of validated `.json` → `write-tier-2-branch` and `write-tier-3-legacy-fallback` catch via `handoff-validate.py` exit-0 assertion
- BRIEF mode inlining PROJECT_STATE.md → `brief-subagent-mode` catches via substring check
- READ silently choosing a brief without surfacing alternatives → `read-multi-brief` catches via chat-response assertion
- RECOVER mutating PROJECT_STATE.md → `recover-degraded` catches via byte-for-byte equality
- RECOVER not re-validating the reconstructed brief → `recover-degraded` catches via `handoff-validate.py` exit-0 assertion
- Generator self-grading → rule stated in BRIEF (anti-self-grade); the former `pipeline-anti-self-grade` eval retired with PIPELINE mode 2026-09-02
- Fresh session auto-reading PROJECT_STATE.md when brief says "do NOT load by default" → `fresh-session-resumes-from-brief` (id 13) catches via file-absence assertion
- READ resuming blind past a moved/deleted `files_read_first` path → `read-drift-missing-file` (id 18) catches via `!! MISSING` + `ACK MISSING`
- READ ignoring a day-old brief without diffing git → `read-drift-stale-brief` (id 19) catches via `!! STALE … ~10d ago` + `ACK STALE`
- READ not surfacing how far HEAD moved since WRITE when `head_sha` is present → `read-drift-commits-since` (id 20) catches via `Commits since brief written:` + `ACK COMMITS`
- Drift checks firing on a fresh, `head_sha`-less brief (false positives / broken back-compat) → `read-drift-clean-brief` (id 21, regression) catches via `DRIFT: clean` + intact `## Resume prompt` scaffold

---

## Future: `claude -p` headless integration eval (deferred to v0.7)

Eval id 13 is a subagent-based test — fast and cheap but uses the parent session's tool config. A higher-fidelity follow-up uses `claude -p` headless to run a real CLI session with real hooks, capture the response, and grade it. Not yet written — no such script exists in any branch (deferred to v0.7+ as part of the Tier 5+ `dogfood-eval` skill or as a `.github/workflows/handoff-resume-eval.yml` CI job once CI has access to an `ANTHROPIC_API_KEY` secret).

See `ROADMAP.md` in the private `projects/catalyst/` planning repo, "Future-work index", for the formal entry.

---

## Run log

Each handoff-touching commit appends a one-line entry to `evals.log` in this dir with date, commit SHA, and pass rate.
