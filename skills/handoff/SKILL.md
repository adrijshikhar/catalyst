---
name: handoff
description: Use when ending a session, switching context, approaching context limits, before /clear or /compact, when starting a fresh session that may have a prior handoff to resume, when context appears degraded, when briefing a subagent for an isolated subtask, or when orchestrating multi-stage work as a pipeline. Operates in four modes — WRITE (save state on the way out), READ (resume cleanly on the way in), RECOVER (rebuild state when degraded), and BRIEF (produce inline minimum-viable context for a subagent) — plus a PIPELINE orchestration that uses BRIEF as the briefing primitive across decompose → route → dispatch → synthesize. Feature-keyed via a three-tier ladder (explicit name → git branch → legacy single-slot), so parallel feature work doesn't clobber state. Use this skill liberally for any session that produced non-trivial decisions, any subagent dispatch that needs scoped context, or any multi-stage task with distinct phases or concerns.
---

# Handoff

A handoff is a **state packet** the next session, subagent, or pipeline stage can act on without re-explanation. Default `/compact` loses crucial details. Default subagent task descriptions either over-share (context bleed) or under-share (the subagent asks clarifying questions it can't actually ask). A proper handoff preserves only what matters, in the structure the next consumer needs.

This skill implements patterns from Anthropic's [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — context resets over compaction, structured artifact handoffs, planner / generator / evaluator separation, sprint contracts, and GAN-inspired iteration loops for subjective work.

## Why two files (and where they live)

One file cannot be both a concise re-entry prompt and a detailed project history. A handoff writes two:

| File | Purpose | Lifetime | Loaded |
|------|---------|----------|--------|
| `<store>/<key>.json` (or `<store>/HANDOFF.json` legacy slot) | **Ephemeral brief** — minimum payload to resume. Points at durable artifacts. | Overwritten on every WRITE for that key. | At the start of the next session for that key. |
| `.claude/PROJECT_STATE.md` | **Persistent narrative** — accreting log of decisions, why, rejected paths, surprises. Project memory. | Prepended forever (newest first). Repo-level — single file. | On demand only — when a brief points the agent at it. |

The brief survives one session boundary per key. The narrative survives the project. PROJECT_STATE.md is intentionally NOT split per feature — cross-feature decisions matter for future features and must be co-located.

## Feature key resolution

WRITE / READ / RECOVER determine the **key** for the brief in this order:

| Priority | Source | Resolved path | When |
|----------|--------|---------------|------|
| 1 | `/handoff <name>` | `<store>/<name>.json` | Explicit override. |
| 2 | `git branch --show-current` (sanitized `/`→`-`, cap 80) | `<store>/<branch>.json` | Default. |
| 3 | Not in a git repo, or detached HEAD | `<store>/HANDOFF.json` | Legacy single-slot fallback. |

`<store>` is the **centralized handoffs dir** printed by `bash "$SCR/handoff-dir.sh"` (or `python3 "$SCR/handoff_paths.py"`): anchored at the MAIN worktree (parent of `git rev-parse --git-common-dir`). Every linked worktree shares ONE store keyed by branch — resume any feature from any worktree. Detect "in a repo?" with `git rev-parse --git-dir` succeeding, never `[ -d .git ]` (`.git` is a file in a worktree). This **supersedes** the earlier per-worktree behavior.

**Sticky session key:** once a WRITE picks a key, subsequent WRITEs / RECOVERs in the same session use the same key. If the user switches branches mid-session, surface the change: "Branch switched. Future handoffs will target `<new-key>.json`. Confirm?"

BRIEF and PIPELINE modes do not persist, so they don't resolve a key — they may *reference* a key when telling a subagent which feature's narrative slice is relevant.

## Four modes (overview)

| Mode | Trigger | Persists? | Consumer |
|------|---------|-----------|----------|
| **WRITE** | Ending session, hitting context limit, before `/clear` or `/compact`, end of pipeline stage, user says "handoff" / `/handoff` | Disk: `<store>/<key>.json` (validated JSON) + prepend `PROJECT_STATE.md` | Next session |
| **READ** | Fresh session with brief(s) present, user wants to resume | None (loads into current context) | Current session |
| **RECOVER** | Context degraded mid-session — re-reads, contradictions, forgotten decisions | Disk: overwrites brief for current key; does NOT prepend narrative | Current session, post-`/clear` |
| **REGROUND** | Mid-session, recall degrading / decisions slipping into the middle | None (read-only re-injection) | Current session |
| **BRIEF** | About to dispatch a subagent and want it to start with the right minimum context | In-memory string passed to Agent tool task description; no disk | Subagent |

The schema for the brief is shared across all four modes. Only persistence and consumer differ.

Plus **PIPELINE** mode — orchestration built on top of BRIEF (decompose → route → dispatch → synthesize). See its own section below.

Do NOT invoke for trivial sessions or one-step subtasks. Three-turn debug doesn't need a handoff. A rename across one file doesn't need a pipeline. Use judgement — if there's nothing a future consumer would lose, skip the skill.

---

## Brief schema (shared, typed)

The brief is a typed JSON document validated against the bundled `brief.schema.json`. WRITE builds it and passes it through `handoff-validate.py` (rejects incomplete/mistyped briefs); READ renders it via `handoff-render.py`. Required fields cannot be omitted — that is the point.

> **Helper-script location (read this first).** The scripts (`handoff-dir.sh`, `handoff-validate.py`, `handoff-render.py`, `handoff_paths.py`) ship **inside the plugin**, NOT in the user's project. Resolve them once at the start of any mode and reuse `$SCR`:
> ```bash
> SCR="${CLAUDE_PLUGIN_ROOT:-.}/scripts"   # consumer project: $CLAUDE_PLUGIN_ROOT is set; inside the catalyst repo it's unset → ./scripts
> ```
> Then call e.g. `bash "$SCR/handoff-dir.sh"` and `python3 "$SCR/handoff-render.py" <key>`. NEVER write a bare relative `scripts/handoff-render.py` into a resume prompt or run it from the user's repo — that path does not exist there. The durable resume entry point for the next session is the slash command **`/catalyst:handoff resume`**, which re-enters this skill and resolves `$SCR` again.

```json
{
  "schema_version": "1",
  "key": "<resolved-key>",
  "timestamp": "<ISO-8601, shell-provided>",
  "mode": "WRITE",
  "resume": { "done_when": "<one verifiable check>", "resume_by": "<one sentence>",
              "prompt": "<optional override>", "history_pointer": "<optional>" },
  "state": {
    "branch": "<branch>", "next_acceptance_check": "<next concrete check>",
    "worktree": { "root": "<$CLAUDE_PROJECT_DIR>", "is_linked": false, "git_common_dir": "<absolute shared .git — git rev-parse --path-format=absolute --git-common-dir>" },
    "diff_summary": "<optional>", "tests": [{"cmd": "...", "result": "pass"}],
    "commands": [], "decisions": [], "rejected_paths": [], "open_risks": []
  },
  "files_read_first": [{"path": "...", "why": "..."}],
  "files_skip": [{"path": "...", "why": "..."}]
}
```

Optional fields with nothing to say are **omitted**, never null/`"none"`. Unknown fields are rejected by the validator (catches typos). `mode` is `WRITE` or `RECOVER` (the persisted modes); BRIEF renders the same shape in-memory without a file.

---

## Mode: WRITE

### Step 1 — Determine the key

Apply the resolution ladder. Sticky within session — if you've already WROTE in this session, reuse that key unless the branch changed (surface the change).

### Step 2 — Gather state

Run in parallel where supported:

```
git branch --show-current
git status --short
git diff --stat
git log --oneline -10
git rev-parse --path-format=absolute --git-common-dir   # state.worktree.git_common_dir
```

Record `state.worktree.git_common_dir` as the **absolute SHARED common dir**. The READ renderer compares it against the resuming session's `git rev-parse --git-common-dir`, so they must be the *same* value.

> **Caution:** In a linked worktree, do **not** use `--absolute-git-dir` — it returns the worktree-private dir (`…/.git/worktrees/<name>`), which will NOT match the renderer's `--git-common-dir` and fires a false `REPO MISMATCH`. Use `--path-format=absolute --git-common-dir` (Git ≥ 2.31). Older Git fallback: `cd "$(git rev-parse --git-common-dir)" && pwd`. In the main checkout both resolve to the same `…/.git`.

From the session transcript, also note: tests run (pass/fail), commands that materially advanced the work, decisions that affect what the next session should do (not every decision — history belongs in the narrative), paths tried and rejected, open risks, the next concrete acceptance check.

### Step 3 — Render the brief

Use the schema above. Include the Resume prompt section with paste-and-go text matching the resolved key. Keep under 200 lines.

### Step 4 — Write to disk

Build the typed object. Write it to a temp file and run `python3 "$SCR/handoff-validate.py" <tmp>.json`; fix every reported field and re-run until it prints `handoff-validate: OK`. Then move it to `<store>/<key>.json` (`<store>` from `"$SCR/handoff-dir.sh"`). Then prepend a narrative entry to `.claude/PROJECT_STATE.md` (unchanged — still markdown).

If `PROJECT_STATE.md` doesn't exist, create it with this header **first**, then add the entry *below* the header:

```markdown
# Project state — narrative log

Accretes over the life of the project. Each handoff prepends a new dated section above earlier entries.
Read sections selectively. The brief at `<store>/<key>.json` is the entry point; this file is the reference.
```

> **Caution:** The header always stays on top. Insert the new entry **immediately after the header block, above existing entries** — never at the absolute top of the file. On a fresh file this means: write the header, then the entry beneath it (not the entry then the header). Verify the first line is still `# Project state` after writing.

Prepend (NOT append) the entry directly below the header, above any existing entries:

```markdown
## <ISO date> — [<key>] <short title>

### What was done
<2-5 bullets>

### Decisions (with rationale)
- **<decision>** — <why>. Rejected: <alternatives>.

### Surprises / lessons
<bullets or omit>

### Pointers
- <path>:<line-range> — <what's there>
```

### Step 5 — Confirm

ALWAYS print the Resume prompt verbatim at the end of the confirmation. The user should never need to open the brief file to find the paste-and-go text.

```
Handoff written (key: <key>, tier: <1|2|3>):
  <store>/<key>.json         (validated JSON)
  .claude/PROJECT_STATE.md   (+<n> lines prepended)

Next session — run `/catalyst:handoff resume` (or paste the Resume prompt):

> resume handoff '<key>': run `/catalyst:handoff resume` (READ mode), then continue. next acceptance check: <one-line check verbatim from the brief>.
```

The resume prompt MUST route through `/catalyst:handoff resume` — never a bare `python3 scripts/handoff-render.py <key>`. The helper scripts live in the plugin, not the user's project, so a relative script path fails everywhere except the Catalyst repo itself. The slash command re-enters this skill, which resolves `$SCR` and renders the brief.

---

## Mode: READ

A new session has loaded with one or more briefs present, and the user wants to resume.

1. Resolve `$SCR` (see Helper-script location), then `<store>` via `bash "$SCR/handoff-dir.sh"`. List `<store>/*.json` (fall back to `<store>/HANDOFF.json` if no keyed files exist).
2. If multiple briefs exist:
   - Detect current branch.
   - Surface ALL briefs. If one matches the current branch (tier-2 match), name it as the primary suggestion.
   - List the others with mtime + key as preview.
   - Wait for the user to confirm. Do NOT silently choose.
3. To resume a key, run `python3 "$SCR/handoff-render.py" <key>` and follow its output. Heed any `!! BRANCH MISMATCH` / `!! REPO MISMATCH` warning before continuing. If the brief was written in a different (linked) worktree — `render` prints `Written in worktree: <root> (linked)` and you're on another branch — tell the user the work lives in `<root>` and offer to `cd` there; don't resume in the wrong tree.
4. Read files listed under `files_read_first` — load-bearing.
5. Do **not** read `.claude/PROJECT_STATE.md` by default. Open it only when the brief explicitly says to, or you hit a decision whose rationale you need.
6. Confirm: "Resumed from `<key>`. Next acceptance check: <quote from brief>. Starting now."
7. The selected key becomes the sticky session key.

If the brief's timestamp is more than ~24h old, diff against current git state before resuming — the working tree may have moved.

---

## Mode: RECOVER

The current session is degraded. Symptoms: agent forgets what it was doing, re-reads files, contradicts earlier decisions, repeats rejected approaches.

1. Determine key via the ladder (same as WRITE).
2. Read existing brief at the resolved path if any.
3. Read most recent 2-3 entries of `.claude/PROJECT_STATE.md`.
4. Run `git log --oneline -20` and `git diff` on the working branch.
5. Reconstruct the typed object from git/transcript, validate it (`python3 "$SCR/handoff-validate.py" <tmp>.json`), and overwrite `<store>/<key>.json`.
6. Do **not** prepend to PROJECT_STATE.md — recovery is re-assembly, not fresh signal.
7. Tell the user: "Recovery brief written at `<store>/<key>.json`. Run `/clear`, then paste this Resume prompt OR run `/catalyst:handoff resume`:" — and ALWAYS print the literal Resume prompt verbatim right below (the Resume prompt comes from `handoff-render.py` output — paste-and-go, not a pointer).

---

## Mode: REGROUND

The current session is still intact but recall is degrading — decisions slip into the low-recall "middle" of the context window, key acceptance checks are being re-derived instead of repeated verbatim, or files-to-keep are being re-read unnecessarily.

REGROUND is a **read-only mid-session re-injection**: it renders only the load-bearing fields of the brief (goal, locked decisions, files to keep in view) as a compact block, then returns. No disk write, no PROJECT_STATE update.

### When to use

- The `session-degradation-watch` hook emits a signal and recommends reground as the per-turn recovery recipe.
- You notice yourself re-reading a file you already have notes on.
- A decision you made earlier is being re-litigated without new information.
- The next acceptance check has drifted from the brief's verbatim wording.

### How to run

```bash
python3 "$SCR/handoff-render.py" --reground <key>
# or with an explicit file path:
python3 "$SCR/handoff-render.py" --reground --file <path>
```

Read the output aloud into the working context, then continue. No branch or repo context is needed — REGROUND is read-only and does not perform any mismatch checks.

### What it emits

- **Goal** — `resume.done_when` + `state.next_acceptance_check`
- **Locked decisions** — `state.decisions` (first five, bulleted)
- **Files to keep in view** — `files_read_first` paths with their `why`

It deliberately omits: `## Summary`, `Written in worktree`, BRANCH MISMATCH, REPO MISMATCH, rejected paths, open risks, diff summary, and the resume prompt. Those belong to READ/RECOVER, not to a mid-session re-grounding.

---

## Mode: BRIEF

You're about to dispatch a subagent for a bounded subtask. The subagent needs the minimum context that makes its job possible — no more.

1. Identify the subtask. Make it concrete.
2. Filter the state packet to fields relevant to that subtask. Drop fields with nothing useful to add (no "none" placeholders).
3. Render the brief inline. It uses the same typed shape, but since it does not persist:
   - Omit `key`, `schema_version`, and any file path (no disk write).
   - The `resume` block becomes `## Task` (named for the subagent's perspective).
4. Keep under **30 lines**. If you can't, the subtask is too broad — re-decompose before dispatching.
5. Pass the rendered brief as the Agent tool's task-description string. Do NOT also pass project-wide narrative — point at the narrative by reference (date / section title), don't inline it.

If the subagent needs a specific PROJECT_STATE.md entry, name it: "see PROJECT_STATE.md `## 2026-05-20 — [feat-jwt-expiry] JWT library migration` if you need the migration rationale" — never paste the entry.

---

## Mode: PIPELINE

Multi-stage orchestration built on top of BRIEF. Patterns codified here track Anthropic's harness-engineering framework — they're not bespoke to Catalyst; they're how Anthropic ships reliable long-running agents.

### Canonical role triad

When a task is large enough to need a pipeline, the default decomposition is into three roles:

| Role | Owns | Context profile |
|------|------|-----------------|
| **Planner** | Expands a high-level prompt into a detailed spec: scope, milestones, success criteria. Ambitious on what to build, **deliberately light on implementation specifics** — planner errors cascade into the generator. | Loads project context, light on tooling. |
| **Generator** | Executes the work — writes code, files, content. Iterates through the units the planner defined. | Heavy on file tools (Edit, Write, Bash), domain-specific context. |
| **Evaluator** | Tests outputs against explicit criteria. Uses LIVE interaction where possible (run app, run tests, navigate UI via Playwright MCP) — not static review of artifacts. | Read-only, with the criteria + the running application/tests, NOT the generator's transcript. |

Variants: **Researcher** = read-only Planner producing findings; **Reviewer** = read-only Evaluator focused on critique; **Implementer** = Generator synonym.

### Sprint contracts

A sprint contract is a two-party agreement on "what done looks like" for a unit of work, established BEFORE the generator codes.

1. Orchestrator (or planner) drafts the next unit's scope + proposed success criteria.
2. A separate evaluator subagent reviews the draft. It may push back ("'tests pass' is too vague — name which tests"), suggest additions ("the diff should not touch src/users/*"), or reject scope creep.
3. Orchestrator iterates the draft until evaluator approves.
4. The approved contract becomes the brief the generator receives.

Without an upfront contract, the generator self-defines "done" and the evaluator grades a moving target. The contract bridges high-level planning ("add JWT leeway") with testable acceptance (`pnpm test src/auth/auth.spec.ts:42-78` passes 6/6, no other tests regress, no edits outside src/auth/").

### Anti-self-grade rule

The generator MUST NOT also be the evaluator. Anthropic's data: "when asked to evaluate work they've produced, agents tend to respond by confidently praising the work — even when, to a human observer, the quality is obviously mediocre."

Enforce by:

- Dispatching the evaluator as a SEPARATE Agent invocation with a fresh context.
- Not feeding the generator's chat transcript into the evaluator's brief. The evaluator sees: the sprint contract + the artifact. Nothing else.
- Never asking the same subagent role to both build and judge in one dispatch.

This is one of the highest-leverage anti-patterns in the whole skill.

### GAN-inspired iteration loop

For subjective domains (design, content, code-for-readability), single-pass evaluation often isn't enough. A bounded iterate loop:

```
generator → artifact → evaluator → score + critique → (if below threshold) generator (refined) → ...
```

- **Max iterations**: 3 (default), 5 (hard cap)
- **Pass threshold**: evaluator-defined; e.g., "design quality ≥ 4/5 on all four axes"
- **Termination on stall**: if two consecutive iterations show no score improvement, stop and surface to user — converged on model's ceiling for this task

Use the loop for: subjective tasks; multiple soft constraints that compete (performance vs readability); creative work.

Do NOT use for: binary pass/fail tasks (tests pass or don't); tasks the generator can verify itself (compile, lint, type-check are deterministic).

Orchestrator owns the loop — generator and evaluator never talk directly.

### Procedure

#### Step 1 — Confirm pipeline-shaped

- Is there really more than one bounded subtask?
- Could this be one fast pass instead?
- Is the user asking for parallelism explicitly, or did you assume?

If "just do it inline", abort. Don't dispatch for a trivial task.

#### Step 2 — Decompose

Pick one axis:

| Axis | Use when | Example |
|------|----------|---------|
| **By concern** | One feature has cross-cutting concerns | API, DB, tests, docs |
| **By module** | The change touches independent modules | payments, notifications, auth |
| **By stage** | Clear pipeline of phases | research → plan → implement → review |

For each subtask: name role (planner/generator/evaluator/etc), inputs needed (pointers, prior-stage outputs), expected output shape.

#### Step 3 — Route

| Pattern | Trigger conditions (ALL hold) | Risk if wrong |
|---------|-------|-------|
| **Parallel** | ≥2 unrelated tasks, no shared state, no file overlap | Merge conflicts, inconsistent state |
| **Sequential** | Any task depends on another's output, or shared files at risk | Wasted time on serialized independent work |
| **Background** | Research / analysis, results not blocking | Lost results if not checked back |

Default when ambiguous: sequential.

#### Step 4 — Surface the plan

Before any dispatch:

```
Pipeline plan:
  Stage 1 (parallel):
    - researcher-A: <subtask> → returns: <output>
    - researcher-B: <subtask> → returns: <output>
  Stage 2 (sequential, depends on Stage 1):
    - planner: <subtask> → returns: <output>
```

User intervenes here if they want a different shape.

#### Step 4.5 — Sprint contract handshake (when generator stage is next)

Before any Generator dispatch, negotiate the sprint contract with the evaluator (see Sprint contracts above). Approved contract becomes the generator's brief. Skip the handshake for stages without a generator (e.g., research-only stages).

#### Step 5 — Brief + dispatch

For each subagent, call BRIEF mode to render the task description. Hand to the Agent tool. Each brief ≤30 lines, no narrative inlined, pointers only.

#### Step 6 — Synthesize

After subagents return, combine outputs into one coherent result. Name the synthesis act in your chat response — "Combining the three reviews:" or "Merging Stage-1 outputs into the plan:". Pasting outputs is NOT synthesis.

| Pipeline shape | What synthesis means |
|----------------|----------------------|
| Multiple files / modules | One coherent commit, no internal contradiction |
| Multi-stage (research → plan → implement) | Each stage consumes prior stage's structured result |
| Parallel review (security + perf + correctness) | One report, unified severity scale, duplicates merged |

If synthesis isn't a clear act, the decomposition was wrong.

#### Step 7 — Optional: save as template

After a successful pipeline:

> "This pipeline worked. Save as `.claude/pipelines/<name>.md` for re-use?"

If yes:

```markdown
# Pipeline: <name>

## When to use
<one sentence describing the trigger shape>

## Decomposition axis
<concern | module | stage>

## Stages
1. **<stage-name>** (parallel | sequential | background)
   - Subagent role: <e.g. researcher, planner>
   - Brief contract: <inputs, expected output>
2. ...

## Synthesis
<how the orchestrator combines stage outputs>
```

v0.3 only writes templates. Reading them back via `/pipeline run <name>` is v0.4.

#### Step 8 — Persist orchestrator state if needed

If your own context grows large during the pipeline, invoke WRITE on the current feature key to preserve synthesis-in-progress. The next session can resume mid-flight.

---

## File layout

```
<store>/                       # centralized handoffs dir ("$SCR/handoff-dir.sh")
├── HANDOFF.json               # legacy / no-git fallback (tier 3)
├── feat-jwt-expiry.json
└── refactor-auth-middleware.json

<project_root>/
├── .claude/
│   ├── PROJECT_STATE.md       # repo-level narrative (still markdown)
│   └── pipelines/             # saved pipeline templates
│       └── audit-then-plan.md
```

All are gitignored by default. Commit them if the team wants shared state.

---

## Migration from v0.2 / v0.3

Legacy `.md` briefs are dropped pre-1.0. No automatic migration:

- v0.3's `.claude/handoffs/*.md` files are not read by the new tooling. Run `"$SCR/handoff-dir.sh"` to locate the new store.
- Re-write any brief you want to keep as a typed JSON using the schema above, validate with `"$SCR/handoff-validate.py"`, and place it in `<store>/`.
- `<store>/HANDOFF.json` is the tier-3 fallback slot (replaces `HANDOFF.md`).

---

## Anti-patterns

- **Inlining file contents into any brief.** Point at paths + line ranges. The consumer has tools.
- **Restating the README.** It's in the repo. Skip.
- **Writing only one of brief / narrative on WRITE.** Both or neither (RECOVER excepted — writes only the brief).
- **Skipping rejected paths.** The next agent will redo them. Highest-ROI entry to write.
- **Vague next-check.** "Continue the work" isn't verifiable. "`pnpm test src/auth/` shows `auth.spec.ts` green" is.
- **Reading the whole narrative on resume.** The brief is the entry point. Narrative is reference.
- **Splitting PROJECT_STATE.md per feature.** The narrative is cross-cutting. Splitting fragments cross-feature memory.
- **Silent key-switching mid-session.** If branch changes, surface the change; don't silently retarget.
- **Writing to tier 3 when tiers 1 or 2 are available.** Legacy fallback is for genuinely no-git cases.
- **Auto-loading every brief in READ mode.** Always select one.
- **BRIEF mode dumping PROJECT_STATE.md into the subagent task description.** Defeats subagent isolation.
- **BRIEF over 30 lines.** Subtask is too broad — re-decompose.
- **PIPELINE for one-step tasks.** Pure overhead. Abort to inline.
- **Parallel dispatch with overlapping file scopes.** Race / merge conflict. Re-route sequential or partition the files.
- **Subagent-to-subagent communication.** Architecturally forbidden. All routing through orchestrator.
- **Synthesis-by-concatenation.** Pasting outputs is not synthesis. Combine, deduplicate, resolve conflicts.
- **Generator grading itself (self-evaluation bias).** Evaluator MUST be a separate subagent with fresh context, given the contract + artifact only (never the generator's transcript). Anthropic's data on self-evaluation bias is unambiguous.
- **Skipping the sprint contract.** Generator self-defines "done", evaluator grades a moving target. Negotiate before the generator codes.
- **Running a GAN loop on binary tasks.** Tests pass or don't — one evaluator pass is enough. The loop is for subjective domains.
- **Invoking the skill for trivial sessions.** Three-turn debug doesn't need this machinery.

---

## Example — good WRITE brief (tier-2 branch)

**Bad** (vague, unvalidated):

```json
{ "key": "feat-jwt-expiry", "notes": "worked on auth, some tests failing, continue tomorrow" }
```

**Good** (typed, validated, immediately actionable):

```json
{
  "schema_version": "1",
  "key": "feat-jwt-expiry",
  "timestamp": "2026-05-24T01:42:00Z",
  "mode": "WRITE",
  "resume": {
    "done_when": "pnpm test src/auth/auth.spec.ts passes 6/6",
    "resume_by": "fix JWT expiry check in src/auth/middleware.ts — add leeway parameter"
  },
  "state": {
    "branch": "feat/jwt-expiry",
    "next_acceptance_check": "pnpm test src/auth/auth.spec.ts passes 6/6",
    "worktree": {"root": "/repo", "is_linked": false, "git_common_dir": "/repo/.git"},
    "diff_summary": "2 files, +18/-6 in src/auth/",
    "tests": [{"cmd": "pnpm test src/auth/auth.spec.ts", "result": "fail"}],
    "decisions": [
      "Use Date.now() (UTC ms) — not new Date() (alloc in hot path)",
      "JWT lib is jose, not jsonwebtoken (see PROJECT_STATE.md 2026-05-20 [feat-jwt-expiry])",
      "Operator is <= not <"
    ],
    "rejected_paths": ["< operator (off-by-one)", "new Date() (alloc)"],
    "open_risks": ["Clock skew not addressed yet"]
  },
  "files_read_first": [
    {"path": "src/auth/middleware.ts", "why": "file under repair"},
    {"path": "src/auth/auth.spec.ts", "why": "failing tests at lines 42-78"}
  ],
  "files_skip": [
    {"path": "src/auth/types.ts", "why": "stable"},
    {"path": "src/users/*", "why": "unrelated"},
    {"path": ".claude/PROJECT_STATE.md", "why": "historical only; decisions above are binding"}
  ]
}
```

The good version answers "what do I do first, what is success, what should I not redo" — and `handoff-validate.py` confirms it is complete before it reaches disk.

---

## Model evolution

Every component of this skill encodes an assumption about what the current model can't do reliably alone:

- **Sprint contracts** assume the generator can't self-define "done" rigorously enough.
- **Canonical role triad** assumes single-context multi-step work degrades.
- **GAN loop** assumes the generator can't self-improve subjective output.
- **BRIEF mode's 30-line ceiling** assumes context bleed is severe enough to require a hard cap.

> *"Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing."* — Anthropic

Review this skill annually (or when a new flagship model lands). Strip scaffolding that no longer earns its complexity. Document removals in PROJECT_STATE.md so the next reviewer knows what was tried and why it was retired.
