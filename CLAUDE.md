# Catalyst — contributor conventions

Repo-local conventions for [Catalyst](https://github.com/adrijshikhar/catalyst). Auto-loaded by Claude Code when working in this repo. Not shipped to plugin users — those conventions live in this file deliberately, not in `skills/`.

When contributing, default to these patterns. Diverge only with a good reason (and write the reason in the commit body).

## Commit conventions

Conventional commits with **mandatory scope** when the change is feature-specific. The scope names the skill or surface.

| Prefix | When | Examples |
|--------|------|----------|
| `feat(<scope>):` | New skill behavior or new surface | `feat(handoff): v0.3 — four modes + PIPELINE with harness-engineering patterns`, `feat(commands): /handoff <name> tier-1 override` |
| `feat:` (no scope) | Repo-wide foundation work | `feat: scaffold Catalyst plugin with handoff skill v0.1` |
| `test(<scope>):` | Add/update evals, fixtures, eval-log records | `test(handoff): add v0.3 eval fixtures`, `test(handoff): record v0.3 iteration-1 eval results` |
| `docs(<scope>):` | Design specs, plans, README, framework notes | `docs(handoff): v0.3 design — feature-keyed handoffs with branch fallback` |
| `ci:` | Workflow + release-pipeline changes | `ci: add release automation adapted from hevoio/hevo-ai-plugin` |
| `chore:` | Version bumps, dep updates, repo-housekeeping | `chore: bump version to 0.1.5 [skip ci]` (always emitted by the auto-release pipeline — never hand-write this) |
| `fix(<scope>):` | Bug fixes | (reserved for when bugs appear) |
| `refactor(<scope>):` | Behavior-preserving structural changes | (reserved) |

**Subject line rules:**
- Imperative mood ("add", "rewrite")
- Em dash `—` separates the headline from elaboration
- Lowercase first word after the colon
- No trailing period

**Body rules:**
- Wrap at ~72 chars
- Lead with the *why*, not the *what*
- Bullet lists for multi-point changes
- Reference specs / plans / commits by relative path or SHA
- Never add `Co-Authored-By` lines (per user's global git rules)

**The `[skip ci]` rule:** appended to the *subject line* of any commit that should not trigger the release pipeline. The auto-release script emits it for version bumps. Don't use it elsewhere.

## Spec → plan → implementation cascade

Three-document workflow for non-trivial features:

```
docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md     ← design contract (the "what" + "why")
docs/superpowers/plans/YYYY-MM-DD-<topic>.md            ← implementation plan (the "how", task-by-task)
skills/<name>/SKILL.md (or commands/, etc.)             ← the implementation
```

Each document has its own commit; they don't get bundled. The spec is approved by the user before the plan is written; the plan is approved before implementation starts.

**Spec doc conventions:**
- Filename: `YYYY-MM-DD-<topic>-design.md`, ISO date prefix, kebab-case topic
- Required sections: `# <Topic> — design spec`, `## TL;DR`, `## Why this exists`, `## Scope` (in / out), topic-specific sections, then `## Open questions`
- When a spec supersedes another, add a `> **SUPERSEDED YYYY-MM-DD** by [target](./target.md). <one-sentence why>.` banner at the top of the old spec. Don't delete — historical context matters.
- Status line: `**Status:** Draft (awaiting user review)` until the user approves, then `**Status:** Approved`

**Plan doc conventions:**
- Filename: `YYYY-MM-DD-<topic>.md` (no `-design` suffix)
- Required header: the exact "For agentic workers" block from `superpowers:writing-plans`
- Tasks numbered `## Task N: <name>`, with explicit `**Files:**` block (Create / Modify / Test paths)
- Each step uses `- [ ] **Step N: <action>**` syntax
- Steps include the exact code or command to run, plus the expected output
- A "Scope addendum" section at the top is allowed when a spec is revised mid-implementation

## Eval-driven development (EDD)

Evals are written **before** the implementation they grade. The repo enforces this by ordering commits: `test(<scope>):` commits land before `feat(<scope>):` commits for the same feature.

| File | Purpose |
|------|---------|
| `skills/<name>/evals/evals.md` | Eval-harness contract — capability list, regression list, graders, thresholds. Markdown, human-readable. |
| `skills/<name>/evals/evals.json` | Test prompts, fixtures, assertions. Machine-readable. Consumed by the subagent eval-runner. |
| `skills/<name>/evals/fixtures/` | Per-eval read-only input files (`.git-HEAD` indicators, fixture handoffs). Committed. |
| `skills/<name>/evals/evals.log` | One line per eval-run, appended (date, commit SHA, pass rate, deferred count). Committed. |
| `skills/<name>-workspace/iteration-N/` | Eval run outputs + `grade.py` + `setup.py`. **Gitignored** via `skills/*-workspace/` rule. |

**Thresholds (project default):**
- Capability evals: `pass@3 ≥ 0.90`
- Regression evals: `pass^3 = 1.00` (release-critical)
- Combined: `pass@1 ≥ 0.75`

**Grader mix:**
- Code graders for deterministic checks (file existence, line counts, regex matches, byte-for-byte equality)
- Model graders (LLM-as-judge) for semantic assertions (synthesis quality, role separation, duplicate merging)
- Human grader only for rare round-trip / brief-schema checks (≤1 per release)

**Anti-self-grade:** when running pipeline evals with a generator + evaluator pattern, the evaluator subagent MUST be a separate Agent invocation with fresh context — never given the generator's transcript. Enforced both in the `handoff` skill itself and as an assertion in eval `pipeline-anti-self-grade`.

## Skill directory layout

Every skill lives at `skills/<name>/` with this canonical shape:

```
skills/<name>/
├── SKILL.md                          # required — YAML frontmatter + body
├── evals/                            # optional but conventional
│   ├── evals.md                      # eval-harness contract
│   ├── evals.json                    # test prompts + assertions
│   ├── evals.log                     # run history (tracked despite *.log gitignore via !skills/*/evals/evals.log)
│   └── fixtures/                     # read-only test inputs
└── references/                       # optional — deeper docs for progressive disclosure
    └── *.md
```

**SKILL.md frontmatter (required):**

```yaml
---
name: <kebab-case-skill-name>
description: <when to trigger, what it does — be specific about contexts and triggering phrases>
---
```

**Description field rules:**
- Lead with "Use when..." or list the trigger contexts up front
- Name the user phrases or commands that should auto-invoke (`handoff`, `/pipeline`, "resume", etc.)
- End with a "Use this skill liberally for..." pushy clause — Catalyst skills lean toward over-triggering, since under-triggering is the dominant failure mode
- Target 80-160 words for substantial skills; shorter for simple ones

**SKILL.md body:**
- Target ≤500 lines for the body (frontmatter excluded)
- Open with a one-paragraph framing of the problem the skill solves
- If grounded in external research, cite it inline with a link (Catalyst cites Anthropic's harness engineering article)
- Use tables for mode comparisons, anti-pattern lists, decision matrices
- Include at least one concrete bad/good example near the end
- Close with a "Model evolution" section when the skill encodes assumptions about model limits that should be reviewed annually

## Hook authoring conventions

Plugin-bundled hooks live in `hooks/` at the repo root. Hook scripts are installed to user projects via the skills' `/install` commands; this directory ships the source.

| Convention | Rule |
|------------|------|
| Filename | `<Event>-<purpose>.sh` (e.g., `PreToolUse-verify-gate.sh`). Lint checks the prefix. |
| Language | POSIX bash + jq only for v0.4-v0.5. No Python deps for portability. |
| Header | Comment block naming the event, what it does, exit codes used, config file path. |
| Robustness | `set -euo pipefail` at the top. Fail-open on infra error (exit 1 → Claude Code ignores hook). |
| Paths | Use `$CLAUDE_PROJECT_DIR`. NEVER touch files outside the project dir except `/tmp` for transient cache. |
| Dependencies | Check for `jq` early. Fail-open if missing. Documented in script header. |
| Decisions | For PreToolUse: emit JSON with `hookSpecificOutput.permissionDecision` ("allow" / "deny" / "ask" / "defer"). For other events: emit `hookSpecificOutput.additionalContext` to inject context. |

See `hooks/README.md` for the full hook protocol reference.

When adding a new hook, use `/hooks new <Event> <name>` to scaffold from the canonical template.

## Evaluator-library conventions

Bundled rubrics live in `skills/evaluator-library/evaluators/<domain>.md`. User overrides live in `.claude/evaluator-library/evaluators/<domain>.md` (per-project). The dispatcher (`scripts/dispatch-evaluator.sh`) checks user dir first, falls back to bundled.

| Convention | Rule |
|------------|------|
| Filename | `<domain>.md` (e.g., `code-quality.md`). Used as the dispatch key. |
| Sections | `### Axes` (4 axes scored 1-5) + `### Score anchors` (5 levels) + `### Critique guidance`. Lint may check this in future. |
| Anti-self-grade | EVERY dispatch via `scripts/dispatch-evaluator.sh` includes a `## Forbidden` block naming the rule. NEVER hand-roll an evaluator brief that skips this. |
| Threshold | Default pass = ≥4 on all axes. Configurable per-project via `.claude/evaluator-library.json`. |

## Pipeline-templates conventions

Bundled templates live in `skills/pipeline-templates/templates/<name>.md`. User-saved templates live in `.claude/pipelines/<name>.md`. Lookup order: user → bundled.

| Convention | Rule |
|------------|------|
| Filename | `<slug>.md`, kebab-case. Slug becomes the `/pipeline run <slug>` key. |
| Required sections | `## When to use`, `## Decomposition axis`, `## Stages`, `## Synthesis`, `## Failure / abort criteria`. All must be present. |
| Stage entries | Numbered list. Each stage names: role, parallel/sequential/background, inputs, expected output. Evaluator-role stages reference `evaluator-library` by domain. |
| Anti-pattern | Don't modify bundled templates — save a user copy to `.claude/pipelines/` instead. Bundled changes will conflict on plugin update. |

## Session-health conventions

`session-health` merges `failure-pattern-detector` (v0.5) and `session-degradation-watch` (v0.6)
into two composing hooks backed by a shared signal library.

- `hooks/UserPromptSubmit-session-health.sh` — per-turn, composes with `UserPromptSubmit-orient.sh`
- `hooks/Stop-session-health.sh` — session-end, composes with `Stop-commit-backstop.sh`
- `hooks/lib/session-health-signals.sh` — shared POSIX bash + jq library (sourced, not executed)

Both Stop hooks fire independently; neither's `additionalContext` overwrites the other.

| Convention | Rule |
|------------|------|
| Log path | `.claude/session-health.log` (configurable). Append-only, one line per alert/detection. |
| Recovery recipe | EVERY alert and EVERY pattern detection names a specific next step. Generic "be careful" recipes are critique failures. |
| Effective window | Thresholds use `effective = advertised × CATALYST_SH_EFFECTIVE_FRAC` (default 0.70). Warn at 0.50×eff, Strong at 0.70×eff. |
| Signal ordering | Per-turn: context STRONG > context WARN > contradiction > stale-read > repeated-tool. One alert per turn — never pile up. |
| Auto-recovery ban | The hook SUGGESTS; it never auto-calls handoff or modifies state. In-loop auto-recovery doesn't work (issue #60248). |
| Token counting | Char-count heuristic (chars / 4). Opt-in tiktoken via `CATALYST_TIKTOKEN=1` + Python + tiktoken. |
| Pattern addition | New patterns ship in `Stop-session-health.sh` + `session-health-signals.sh`. Each gets an entry in `enabled_patterns` config + a SKILL.md row. |
| Composition | Both hooks compose additively. settings.json `.hooks.UserPromptSubmit` / `.hooks.Stop` are arrays — multiple entries fire in order. |
| Canonical config | `.claude/catalyst.json` (optional) is the single config source for hook knobs; per-skill sections (`session_health`, `verify_gate`). Precedence: env > json > default. Absent file = defaults. |

*(Session-degradation-watch and failure-pattern-detector are retired — unified under **Session-health conventions** above. Brain-bridge was retired 2026-06-17; source archived in the private projects repo at `catalyst/archived/brain-bridge/`.)*

## Commands as thin wrappers

Slash commands live at `commands/<name>.md`. They are deliberately thin — the skill holds the logic, the command names the entry point.

```markdown
---
description: <when to use this command — one sentence>
---

Invoke the `<skill-name>` skill in <mode> mode.

[Optional: argument handling, mode routing, special-keyword interpretation]
```

Argument handling pattern (from `commands/handoff.md`):
- `$ARGUMENT` matched against recognized keywords first (`read`, `resume`, `recover`, `rebuild` route to specific modes)
- Otherwise treated as a tier-1 explicit key
- Empty argument falls through to default behavior

## Plugin manifest + marketplace

`.claude-plugin/plugin.json` is the source of truth for version. Edit it directly for minor/major bumps; patch bumps are auto-emitted by the release pipeline.

`.claude-plugin/marketplace.json` makes Catalyst its own one-plugin marketplace. Install via `/plugin marketplace add adrijshikhar/catalyst && /plugin install catalyst@catalyst`.

**Required plugin.json fields:** `name`, `version`, `description`, `license`. Lint checks this via `scripts/lint.py`.

## Release pipeline

**Auto-release on push to `main` is DISABLED.** `.github/workflows/release.yml` is
`workflow_dispatch`-only — it no longer fires on merge. Version bumps are manual.

To cut a release:

1. Hand-edit `.claude-plugin/plugin.json` to set the target version (`MAJOR.MINOR.PATCH`).
2. Merge that change to `main` via PR (won't trigger any release).
3. Run the pipeline manually when you want the tag + GitHub Release:
   ```bash
   gh workflow run release.yml -R adrijshikhar/catalyst --ref main
   ```
   `scripts/release.sh` bumps the patch, commits `chore: bump version to X.Y.Z [skip ci]`,
   tags `vX.Y.Z`, pushes both, then `gh release create` generates notes.

**Re-enabling auto-release:** restore the `push: branches: [main]` trigger in
`release.yml`. The loop guards remain intact — the job-level `if` skips the CI's
own bump commits (by `github-actions[bot]` committer identity) and any `[skip ci]`
subject, so two layers of loop defense are ready if the push trigger returns.

## Gitignore conventions

| Pattern | Reason |
|---------|--------|
| `*.log` | Generic — most logs are noise |
| `!skills/*/evals/evals.log` | Override — eval logs are the regression trace and must be durable |
| `.claude/handoffs/`, `.claude/HANDOFF.md`, `.claude/PROJECT_STATE.md` | Per-user/repo handoff state — never committed unless team wants shared briefs |
| `skills/*-workspace/` | Eval run scratch — outputs, graders, snapshots |
| `.DS_Store`, `.idea/`, `.vscode/`, `*.swp` | Standard editor/OS noise |

When adding new eval artifacts, decide explicitly: regression-trace-durable (commit) vs scratch (gitignore).

## CI lint

`scripts/lint.py` runs on every push and PR via `.github/workflows/ci.yml`. It validates:

1. `.claude-plugin/plugin.json` is valid JSON with required fields
2. `.claude-plugin/marketplace.json` is valid JSON with `name`, `owner`, `plugins`
3. Every `skills/*/SKILL.md` has YAML frontmatter with `name` and `description`
4. Every `commands/*.md` has YAML frontmatter with `description`

Lint failures block the release. Fix lint locally with `python3 scripts/lint.py` before pushing.

`scripts/lint.py` also runs deterministic breadth checks: invisible-unicode / ASCII-smuggling scan, `description:` block-scalar guard, no-personal-paths, settings.json hook-schema validation, markdown file-ref resolution (`.md` only, code-stripped, gitignore-aware), and a catalog/drift gate (README skill-count + marketplace name consistency).

## CI evaluation — two lanes

Catalyst CI runs in two lanes (see the CI+eval/perf infra design spec, archived in the private `projects` repo):

- **Lane A — PR-blocking, deterministic, free.** `scripts/lint.py` (structure + breadth checks above), `python3 -m unittest discover tests`, `scripts/eval-grade.py` (grades committed snapshots), and the hook functional smoke (`tests/sh/test_hook_smoke.sh`). No model, no `ANTHROPIC_API_KEY`.
- **Lane B — local-generate / CI-grade.** `scripts/eval-run.py` runs each skill's `evals.json` prompts through the developer's authenticated `claude` CLI and commits transcripts + `skills/<name>/evals/snapshots/results.json`. Regenerate locally when SKILL.md changes; CI only grades, never generates.

| Rule | Detail |
|------|--------|
| No model in CI | `eval-run.py` is local-only. CI runs `eval-grade.py` against committed snapshots; missing snapshots WARN (not fail). |
| Snapshot metadata | Every `results.json` pins `generated_at` (via `--now`), commit SHA, SKILL.md sha256, CLI version, model. |
| Determinism at the leaf | Every graded assertion bottoms out in exists/contains — never model narration. |
| Reporting | Eval reports show median/min/max/stdev, never mean alone. |
| `--now` | `eval-run.py` takes the timestamp as an argument (shell-provided); no in-script clock calls. |
| Hook smoke | Runs each hook in a throwaway temp git repo so `Stop-commit-backstop` never touches the real tree. |

## Skills vs repo conventions

Hard rule about scope:

- **Skills** at `skills/<name>/` = behavior shipped to every plugin user. Generic, reusable, model-evolution aware.
- **This `CLAUDE.md`** = conventions specific to contributing to `adrijshikhar/catalyst`. Repo-local only. Never put repo-internal conventions in `skills/` — they propagate to plugin users who don't need them.

If the work being done is "how to contribute to Catalyst", it belongs in this file. If it's "what should Claude do in any project that uses the plugin", it belongs in a skill.

## Anti-patterns

- **Skipping the spec → plan → implementation cascade for non-trivial work.** Skip only for trivial fixes (typos, dep bumps).
- **Writing the implementation before the evals.** Test files come first. The repo enforces this by commit order.
- **Hand-writing `chore: bump version` commits.** The auto-release pipeline owns these. Manual bumps confuse the loop guard.
- **Adding `Co-Authored-By` lines.** Disabled globally per user prefs.
- **Splitting changes that should be one commit into many small commits to satisfy a rule.** Conventional commits are about clarity, not granularity for its own sake.
- **Bundling unrelated changes into one commit.** Each commit should be one logical change.
- **Committing eval workspace output.** The `skills/*-workspace/` gitignore exists for a reason.
- **Deleting superseded specs instead of marking them with a banner.** Historical specs explain why current ones are shaped the way they are.
- **Shipping repo-internal conventions as a skill.** Repo conventions belong in this `CLAUDE.md`, not in `skills/`.

## Quick reference — when adding a new skill

1. **Brainstorm** with the user via `superpowers:brainstorming` skill
2. **Spec:** write `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, commit `docs(<scope>):`
3. **Plan:** write `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`, commit `docs(<scope>):` (or omit, depending on plan stability)
4. **Evals first:** write `skills/<name>/evals/evals.md` + `evals.json` + `fixtures/`, commit `test(<scope>):`
5. **Skill:** write `skills/<name>/SKILL.md`, commit `feat(<scope>):`
6. **Command (if applicable):** write `commands/<name>.md`, commit `feat(commands):`
7. **Run evals:** workspace at `skills/<name>-workspace/iteration-1/`, dispatch subagents, grade, aggregate, viewer
8. **Record results:** append to `skills/<name>/evals/evals.log`, commit `test(<scope>):`
9. **Push:** auto-release pipeline bumps version + tags + publishes

For minor/major release: edit `plugin.json` manually before the push that should trigger the bump.

## Model evolution

This conventions doc encodes assumptions about how the repo is run today:

- **Spec → plan cascade** assumes implementers benefit from upfront alignment. As models improve at one-shot multi-step work, the plan step may become optional.
- **EDD-first commit ordering** assumes evals are cheap to write and expensive to add post-hoc. May relax as models grow better at generating evals from a finished skill.
- **Manual minor/major version bumps** assume the maintainer wants control over those milestones.
- **Conventional commit scopes** assume readers scan logs by feature. May relax if a richer changelog tool replaces raw git log scanning.

Review annually or when a new flagship model lands. Strip rules that no longer earn their complexity. Conventions are observations, not commandments.
