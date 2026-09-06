# EVAL DEFINITION: hooks skill v0.4

**Skill:** `hooks` (Catalyst v0.4)
**Defined:** 2026-05-24 (pre-implementation — EDD)
**Spec:** `docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md`

---

## Capability evals (5)

| ID | Name | What it proves |
|----|------|----------------|
| 0 | install-single-precompact | `/hooks install PreCompact` adds entry to settings.json + copies script to .claude/hooks/ |
| 1 | install-all | `/hooks install --all` adds both lifecycle hooks (PreCompact, SessionStart) idempotently |
| 2 | uninstall-removes-cleanly | `/hooks uninstall PreCompact` removes settings.json entry + deletes hook script |
| 3 | new-event-scaffold | `/hooks new PostToolUse my-custom-hook` produces a valid hook script template at hooks/PostToolUse-my-custom-hook.sh |
| 4 | lint-catches-bad-matcher | `/hooks lint <path>` flags a hook with matcher ".*" as too broad |

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


## 2026-09-06 — evals 0–2 retired

`/hooks install`, `/hooks install --all` and `/hooks uninstall` were removed in v0.9.0 (plugin-native hooks); evals 0–2 tested them and are dropped. Evals 3 (`/hooks new` scaffold) and 4 (`/hooks lint`) remain and are the first hooks evals ever seeded.

## Run mechanics (Lane B, 2026-09-06)

`scripts/eval-run.py --skill <name> --model <m> --runs 3 --now <iso>` runs every prompted eval
through `claude -p` in a **fresh temp workspace per run**: the eval's `files[]` are
materialized, a `.git-HEAD` fixture becomes a real branch, fixture trees the prompt names
under `skills/<name>/evals/fixtures/` are copied in at the same relative path, and `scripts/`
is symlinked to the checkout so `python3 scripts/handoff-*.py` resolves. The plugin under
test is the working tree (`--plugin-dir`), not the installed cache. Each run's transcript
and every file it wrote are captured into `evals/snapshots/` with model, commit, SKILL.md
and evals.json hashes stamped.

`scripts/eval-grade.py` (Lane A, CI) re-applies the assertions against transcript + captured
files. Deterministic grammar — anything else is UNGRADED and counts as failed:

| Form | Graded as |
|---|---|
| `<path> exists` | a captured file path ends with `<path>` |
| `… written to / created at <path>` | same |
| `… NOT written / does NOT exist / No … was written … <path>` | no captured path matches |
| `` `<cmd>` exits 0 `` | cmd run against the captured files (`scripts/` → checkout) |
| `<file> passes 'bash -n' …` | `bash -n` on the captured file |
| `Brief state.<field> is <value>` / `mentions <needles>` | JSON field of a captured handoffs/*.json |
| `<file> names/quotes … 'needle' or path` | needles inside that file |
| `rendered output of `<cmd>` contains …` | run cmd, needles in stdout |
| `Chat response names <phrase> (…)` | phrase in transcript, case-insensitive |
| quoted `'needle'`s | all in transcript+files; ` OR ` / `at least one of` → any |

Model default for seeds: **Sonnet** (Haiku dry run 2026-09-06 did not invoke the skill at all
and wrote its own JSON; Sonnet invoked `catalyst:handoff` and followed the key ladder).
Gating: `eval-grade --enforce` fails on missing/stale snapshot, capability pass@3 < 0.90,
regression pass^3 < 1.00.
