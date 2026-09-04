# Catalyst — contributor conventions

Repo-local conventions for [Catalyst](https://github.com/adrijshikhar/catalyst). Auto-loaded by Claude Code when working in this repo. Not shipped to plugin users — those conventions live in this file deliberately, not in `skills/`.

When contributing, default to these patterns. Diverge only with a good reason (and write the reason in the commit body).

## Commit conventions

Conventional commits with **mandatory scope** when the change is feature-specific. The scope names the skill or surface.

| Prefix | When | Examples |
|--------|------|----------|
| `feat(<scope>):` | New skill behavior or new surface | `feat(handoff): v0.3 — four modes + PIPELINE with harness-engineering patterns`, `feat(commands): /handoff <name> tier-1 override` |
| `feat:` / `docs:` (no scope) | Repo-wide foundation work, or a docs change spanning CI + conventions + version rather than one feature | `feat: scaffold Catalyst plugin with handoff skill v0.1`, `docs: v0.8.0 surface — CI parity, CLAUDE.md/CONTRIBUTING, plugin.json 0.8.0` |
| `test(<scope>):` | Add/update evals, fixtures, eval-log records | `test(handoff): add v0.3 eval fixtures`, `test(handoff): record v0.3 iteration-1 eval results` |
| `docs(<scope>):` | Design specs, plans, README, framework notes | `docs(handoff): v0.3 design — feature-keyed handoffs with branch fallback` |
| `ci:` | Workflow + release-pipeline changes | `ci: add release automation adapted from hevoio/hevo-ai-plugin` |
| `chore:` | Version bumps, dep updates, repo-housekeeping | `chore: bump version to 0.1.5 [skip ci]` (emitted by `scripts/release.sh` when `release.yml` is dispatched manually — never hand-write this) |
| `fix(<scope>):` | Bug fixes | (reserved for when bugs appear) |
| `refactor(<scope>):` | Behavior-preserving structural changes. A change that alters behavior is `feat`/`fix`, even when it looks structural — breaking changes take a `!` suffix on any type (`feat(scope)!:`) plus a `BREAKING CHANGE:` footer. (`ca73f08` predates this rule and used `refactor!`.) | `refactor(hooks): single store resolver in lib/config.sh` |

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

**The `[skip ci]` rule:** appended to the *subject line* of any commit that should not trigger CI/release workflows. `scripts/release.sh` emits it for version bumps (run via manual `release.yml` dispatch — see "Release pipeline"). Don't use it elsewhere.

## Spec → plan → implementation cascade

Three-document workflow for non-trivial features:

```
<private projects repo>/catalyst/specs/YYYY-MM-DD-<topic>-design.md   ← design contract (the "what" + "why")
<private projects repo>/catalyst/plans/YYYY-MM-DD-<topic>.md          ← implementation plan (the "how", task-by-task)
skills/<name>/SKILL.md (or commands/, etc.)                            ← the implementation
```

Specs and plans live in the maintainer's private `projects` repo (`projects/catalyst/{specs,plans}/`), not here — `docs/superpowers/` and `docs/ROADMAP.md` are gitignored in this repo. The public repo carries only `docs/HARNESS.md`.

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

**Anti-self-grade:** whenever an evaluator or reviewer subagent grades an artifact, it MUST be a separate Agent invocation with fresh context — never given the generator's transcript. Stated as a rule in `handoff` BRIEF mode (the `evaluator-library` skill and eval `pipeline-anti-self-grade` that used to enforce it were retired in the 2026-09-02 v0.7.0 strip).

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
- Name the user phrases or commands that should auto-invoke (`handoff`, `/hooks`, "resume", etc.)
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

Plugin-bundled hooks live in `hooks/` at the repo root and are declared natively in
`hooks.json` at the repo root — there is no per-project install step; see below.

| Convention | Rule |
|------------|------|
| Filename | `<Event>-<purpose>.sh` (e.g., `SessionStart-handoff-read.sh`). Lint checks the prefix. |
| Language | POSIX bash + jq only for v0.4-v0.5. No Python deps for portability. |
| Header | Comment block naming the event, what it does, exit codes used, config file path. |
| Robustness | `set -euo pipefail` at the top. Fail-open on infra error (exit 1 → Claude Code ignores hook). |
| Paths | Use `$CLAUDE_PROJECT_DIR`. Commands in declaration files use `"${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/<script>.sh"`. NEVER touch files outside the project dir except `/tmp` for transient cache. |
| Dependencies | Check for `jq` early. Fail-open if missing. Documented in script header. |
| Decisions | For SessionStart: emit JSON with `hookSpecificOutput.additionalContext` to inject context. For PreCompact: emit top-level `systemMessage` only — `hookSpecificOutput` fails schema validation on that event (`tests/sh/test_hook_smoke.sh` enforces this). |
| Output + exit | Emit the event's JSON directly with `jq -n` as the last statement; exit 1 on infra error (jq missing). Two hooks, two emission sites — no shared writer. |

See `hooks/README.md` for the full hook protocol reference.

When adding a new hook, use `/hooks new <Event> <name>` to scaffold from the canonical template.

**Plugin-shipped hooks are declared once, not installed.** One file, `hooks.json` at the repo
root, serves every host: Claude Code and Codex read it because `.claude-plugin/plugin.json`
declares `"hooks": "./hooks.json"` (both honour a path string there), and Antigravity CLI
auto-discovers a root `hooks.json` — it never looks in `hooks/`. Never move it back under
`hooks/`: lint fails, and Antigravity would silently lose the hooks.
`scripts/lint.py`'s `check_hooks_json` enforces: known events, `SessionStart` matcher `""`
(match-all — matcher values for that event are exact-match over
`startup | resume | clear | compact | fork`), the cross-host command form, and that every
referenced script exists and is executable.

## Configuration knobs

`.claude/catalyst.json` is the canonical knobs file, read through one reader per
language — `hooks/lib/config.sh` (bash, sourced by hooks) and
`scripts/catalyst_config.py` (Python, used by scripts). Precedence is
**env > json > built-in default**.

Env names derive mechanically: `CATALYST_` + the dotted key uppercased with `.` → `_`.
So `handoff.stale_hours` is overridden by `CATALYST_HANDOFF_STALE_HOURS`. Never add a
lookup table — the rule is the contract.

| Key | Default | Consumer |
|-----|---------|----------|
| `handoff.stale_hours` | `24` | `handoff-render.py` READ `!! STALE` |
| `handoff.brief_max_lines` | `30` | `handoff-render.py --brief` |
| `hooks.precompact_prompt` | `true` | `PreCompact-handoff-write.sh` |
| `hooks.sessionstart_resume` | `true` | `SessionStart-handoff-read.sh` |

Structured values (arrays/objects) have **no** env form and are read with
`catalyst_config_json` / `get_json`. The scalar reader returns the default for them
rather than stringifying a structure.

The two `hooks.*` boolean knobs accept `false` / `0` / `no` / `off`
(case-insensitive) as disabled; anything else — including a missing or malformed
config — is enabled. That parsing lives in **exactly one place**,
`catalyst_config_enabled` in `hooks/lib/config.sh`. A hook that spells out its own
falsy check is duplicating load-bearing parsing; there is no lint guard for this
one, so it is enforced by review.

**Shared bash libraries live in `hooks/lib/`, not `scripts/`.** Hooks run from the
plugin tree (declared in `hooks.json`, commands rooted at
`${CLAUDE_PLUGIN_ROOT}`), so `$SCRIPT_DIR/lib/` resolves inside the plugin itself —
no copy step, nothing to reap. A helper a hook needs must still live in `hooks/lib/`,
not `scripts/`. `scripts/lint.py` fails the build if a hook re-inlines the store
resolver instead of sourcing `lib/config.sh`.

## Retired surfaces

Retired 2026-09-02 in the v0.7.0 strip (spec: `projects/catalyst/specs/2026-09-02-v0.7-strip-design.md` in the private planning repo): `session-health` (+ `catalyst-stats`), `evaluator-library`, `pipeline-templates`, handoff SPLIT and PIPELINE modes, the `UserPromptSubmit-orient` and `Stop-commit-backstop` hooks, and verify-gate's opt-in over-reliance rule. Full source + restore steps for each live under `projects/catalyst/archived/<name>/` (as `brain-bridge`, retired 2026-06-17, already does). Do not re-add any of them without a new spec naming the demand signal.

Retired 2026-09-03 in the v0.9.0 plugin-native-hooks change (spec: `projects/catalyst/specs/2026-09-03-plugin-native-hooks-design.md`): `scripts/install-hooks.sh`, `scripts/hooks-status.sh`, `/hooks install`, `/hooks uninstall`, `/verify-gate install`, `/verify-gate uninstall`. Hooks are declared in `hooks/hooks.json` and run from the plugin cache; `scripts/hooks-config.sh` (`status` / `enable` / `disable`) replaced the installer's status surface at a fraction of the size. Do not re-add an installer without a new spec naming the demand signal — the wager it made (installed hooks can fall behind the plugin) is structurally impossible under `hooks.json` delivery.

Retired 2026-09-04 (spec: `projects/catalyst/specs/2026-09-03-provider-agnostic-delivery-design.md`, rev 5): `verify-gate` (hook, skill, `/verify-gate`, `scripts/verify-gate-config.sh`, two suites, `verify_gate.*` knobs), `hooks/lib/host.sh`, `hooks/lib/transcript.sh`. Archived under `projects/catalyst/archived/verify-gate/`. Demand signal to restore: a user running an autonomous loop asks for a claim-file gate.

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

Two manifests. `.claude-plugin/plugin.json` is read by Claude Code, and by Codex and Copilot as a
legacy-format manifest. Root `plugin.json` is Antigravity CLI's (name, version, description) and is
deliberately **schema-less** — lint fails on a `$schema` key — because a root Agent Plugins manifest
makes Codex exclude hooks
from Agent Plugins-format packages (`openai/codex` PR #37027, still on main), and Catalyst's
hooks are the product. Re-adding the standard is a one-file change once that boundary lifts —
check `codex-rs/core-plugins/src/loader.rs` for the `PluginManifestFormat::AgentPlugin` hook
gate before doing so. `scripts/release.sh` bumps both manifests; lint asserts their `version` fields are equal.

Host support statements must never outrun evidence (P2): Claude Code and Codex run the two hooks (Codex only after the user's one-time `/hooks` trust step); Copilot is Claude-format compatible per VS Code docs and stays "unverified" in every doc until a live run proves it; every other host is unsupported until Codex allows hooks in Agent Plugins packages; slash commands are Claude Code only.

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

**Minor and major releases must be hand-tagged.** `scripts/release.sh` computes
`NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"` — it can only ever bump the patch.
Dispatching `release.yml` after merging a `0.8.0` `plugin.json` would therefore tag
`v0.8.1` and skip `v0.8.0` entirely. Both v0.7.0 and v0.8.0 were released this way:

```bash
# after the version-bump PR is merged and plugin.json on main reads X.Y.0
git checkout main && git pull
git tag -a vX.Y.0 -m "Release X.Y.0"
git push origin vX.Y.0
gh release create vX.Y.0 --title "Catalyst X.Y.0" --generate-notes
```

The maintainer creates the tag, so `release.yml`'s committer-based loop guard is
never involved and no `chore: bump version` commit is produced. Patch releases
resume the normal dispatch afterwards.

## Gitignore conventions

| Pattern | Reason |
|---------|--------|
| `*.log` | Generic — most logs are noise |
| `!skills/*/evals/evals.log` | Override — eval logs are the regression trace and must be durable |
| `.claude/handoffs/`, `.claude/HANDOFF.md`, `.claude/PROJECT_STATE.md` | Per-user/repo handoff state — never committed unless team wants shared briefs |
| `.claude/catalyst.json` | Per-project config knobs — see "Configuration knobs" above |
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

- **Lane A — PR-blocking, deterministic, free.** `bash scripts/test.sh`, invoked as a single CI step so the local gate and the PR gate cannot drift: `scripts/lint.py`, `python3 -m unittest discover tests`, `scripts/eval-grade.py`, and the shell suites (`test_hook_smoke`, `test_hooks_config`, `test_catalyst_config`, `test_catalog`). No model, no `ANTHROPIC_API_KEY`.
- **Lane B — local-generate / CI-grade.** `scripts/eval-run.py` runs each skill's `evals.json` prompts through the developer's authenticated `claude` CLI and commits transcripts + `skills/<name>/evals/snapshots/results.json`. Regenerate locally when SKILL.md changes; CI only grades, never generates.

| Rule | Detail |
|------|--------|
| No model in CI | `eval-run.py` is local-only. CI runs `eval-grade.py` against committed snapshots; missing snapshots WARN (not fail). |
| Snapshot metadata | Every `results.json` pins `generated_at` (via `--now`), commit SHA, SKILL.md sha256, CLI version, model. |
| Determinism at the leaf | Every graded assertion bottoms out in exists/contains — never model narration. |
| Reporting | Eval reports show median/min/max/stdev, never mean alone. |
| `--now` | `eval-run.py` takes the timestamp as an argument (shell-provided); no in-script clock calls. |
| Hook smoke | Runs each hook in a throwaway temp git repo so no hook ever touches the real tree. |

## Skills vs repo conventions

Hard rule about scope:

- **Skills** at `skills/<name>/` = behavior shipped to every plugin user. Generic, reusable, model-evolution aware.
- **This `CLAUDE.md`** = conventions specific to contributing to `adrijshikhar/catalyst`. Repo-local only. Never put repo-internal conventions in `skills/` — they propagate to plugin users who don't need them.

If the work being done is "how to contribute to Catalyst", it belongs in this file. If it's "what should Claude do in any project that uses the plugin", it belongs in a skill.

## Anti-patterns

- **Skipping the spec → plan → implementation cascade for non-trivial work.** Skip only for trivial fixes (typos, dep bumps).
- **Writing the implementation before the evals.** Test files come first. The repo enforces this by commit order.
- **Hand-writing `chore: bump version` commits.** `scripts/release.sh` (via manual `release.yml` dispatch) owns these. Manual bumps confuse the loop guard.
- **Adding `Co-Authored-By` lines.** Disabled globally per user prefs.
- **Splitting changes that should be one commit into many small commits to satisfy a rule.** Conventional commits are about clarity, not granularity for its own sake.
- **Bundling unrelated changes into one commit.** Each commit should be one logical change.
- **Committing eval workspace output.** The `skills/*-workspace/` gitignore exists for a reason.
- **Deleting superseded specs instead of marking them with a banner.** Historical specs explain why current ones are shaped the way they are.
- **Shipping repo-internal conventions as a skill.** Repo conventions belong in this `CLAUDE.md`, not in `skills/`.

## Quick reference — when adding a new skill

1. **Brainstorm** with the user via `superpowers:brainstorming` skill
2. **Spec:** write `projects/catalyst/specs/YYYY-MM-DD-<topic>-design.md` (private planning repo), commit `docs(<scope>):`
3. **Plan:** write `projects/catalyst/plans/YYYY-MM-DD-<topic>.md` (private planning repo), commit `docs(<scope>):` (or omit, depending on plan stability)
4. **Evals first:** write `skills/<name>/evals/evals.md` + `evals.json` + `fixtures/`, commit `test(<scope>):`
5. **Skill:** write `skills/<name>/SKILL.md`, commit `feat(<scope>):`
6. **Command (if applicable):** write `commands/<name>.md`, commit `feat(commands):`
7. **Run evals:** workspace at `skills/<name>-workspace/iteration-1/`, dispatch subagents, grade, aggregate, viewer
8. **Record results:** append to `skills/<name>/evals/evals.log`, commit `test(<scope>):`
9. **Merge via PR**, then cut the release deliberately: `gh workflow run release.yml -R adrijshikhar/catalyst --ref main` (see "Release pipeline"). Nothing publishes on push.

For minor/major release: edit `plugin.json` manually via PR before dispatching `release.yml`.

## Model evolution

This conventions doc encodes assumptions about how the repo is run today:

- **Spec → plan cascade** assumes implementers benefit from upfront alignment. As models improve at one-shot multi-step work, the plan step may become optional.
- **EDD-first commit ordering** assumes evals are cheap to write and expensive to add post-hoc. May relax as models grow better at generating evals from a finished skill.
- **Manual releases (all bumps via dispatched `release.yml`)** assume the maintainer wants control over when a version ships.
- **Conventional commit scopes** assume readers scan logs by feature. May relax if a richer changelog tool replaces raw git log scanning.

Review annually or when a new flagship model lands. Strip rules that no longer earn their complexity. Conventions are observations, not commandments.
