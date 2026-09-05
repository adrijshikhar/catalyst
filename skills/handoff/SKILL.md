---
name: handoff
description: Use when handing a task to a native subagent or an external agent, ending a session, switching context, approaching compaction, resuming a prior handoff, or recovering degraded context. Five modes — WRITE saves a session checkpoint, READ resumes it, RECOVER rebuilds it, REGROUND re-injects its essentials, and BRIEF delegates a selected task with an explicit completion contract. BRIEF dispatches native subagents directly; external agents receive a self-contained task file and short launch prompt by default, with inline output only on explicit request. Trigger phrases include "handoff this to a subagent", "handoff this to Codex", "brief a subagent", "handoff", "resume", and "reground". Use this skill liberally for decisions worth preserving and isolated tasks worth delegating.
---

# Handoff

A handoff is a **state packet** the next session or subagent can act on without re-explanation. Default `/compact` loses crucial details. Default subagent task descriptions either over-share (context bleed) or under-share (the subagent asks clarifying questions it can't actually ask). A proper handoff preserves only what matters, in the structure the next consumer needs.

This skill implements patterns from Anthropic's [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — context resets over compaction, structured artifact handoffs, pre-coding contracts, and generator ≠ evaluator separation for subagent briefs.

## Session checkpoints: two files

One file cannot be both a concise re-entry prompt and a detailed project history. A session WRITE writes two:

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

**Canonical storage:** `<store>` is `<main>/.catalyst/handoffs/`, regardless of host. Outside Git, `<main>` is the current directory. New writes always use this path. Readers also find the same key under `<main>/.claude/handoffs/` when its canonical file is absent; old files are never automatically moved or deleted. Inventory lists both locations with paths.

**Before writing state:** run `python3 "$SCR/handoff_paths.py" --init` for checkpoints, or add `--tasks` for task files. This initializes only the selected store and, in Git, ensures `.catalyst/` is in the main worktree's `.gitignore`, preserving existing contents. Failure means stop before writing and report the path/error. Outside Git, no `.gitignore` is created. Already tracked files remain tracked; never untrack user files automatically. Lookup, READ, REGROUND and hooks stay read-only. Existing `.claude/catalyst.json` config and `.claude/PROJECT_STATE.md` narrative locations are unchanged.

**Sticky session key:** once a WRITE picks a key, subsequent WRITEs / RECOVERs in the same session use the same key. If the user switches branches mid-session, surface the change: "Branch switched. Future handoffs will target `<new-key>.json`. Confirm?"

BRIEF uses a task name, never the sticky session key. External task files live separately under `<main>/.catalyst/tasks/`; BRIEF never writes a session checkpoint or project narrative.

## Five modes (overview)

| Mode | Trigger | Persists? | Consumer |
|------|---------|-----------|----------|
| **WRITE** | Ending session, hitting context limit, before `/clear` or `/compact`, user says "handoff" / `/handoff` | Disk: `<store>/<key>.json` (validated JSON) + prepend `PROJECT_STATE.md` | Next session |
| **READ** | Fresh session with brief(s) present, user wants to resume | None (loads into current context) | Current session |
| **RECOVER** | Context degraded mid-session — re-reads, contradictions, forgotten decisions | Disk: overwrites brief for current key; does NOT prepend narrative | Current session, post-`/clear` |
| **REGROUND** | Mid-session, recall degrading / decisions slipping into the middle | None (read-only re-injection) | Current session |
| **BRIEF** | Delegate a selected task to a subagent or external agent | Native: tool argument. External: task Markdown file by default | Task recipient; completion returns to originator |

Session modes share the typed checkpoint schema. Native BRIEF reuses its task fields with optional `scope` and `return_instructions` strings (BRIEF-only, not checkpoint fields). External BRIEF uses the Markdown task template below.

To fork a braided session into separate threads, WRITE once per thread with an explicit key: `/catalyst:handoff <key-a>`, then `/catalyst:handoff <key-b>`.

For automatic checkpoint suggestions, skip trivial sessions with nothing to preserve. Always honor an explicit task-handoff request, including a small subtask.

---

## Brief schema (shared, typed)

The brief is a typed JSON document validated against the bundled `brief.schema.json`. WRITE builds it and passes it through `handoff-validate.py` (rejects incomplete/mistyped briefs); READ renders it via `handoff-render.py`. Required fields cannot be omitted — that is the point.

> **Helper-script location (read this first).** The scripts (`handoff-dir.sh`, `handoff-validate.py`, `handoff-render.py`, `handoff_paths.py`) ship **inside the plugin**, NOT in the user's project. Resolve them once at the start of any mode and reuse `$SCR`:
> ```bash
> SCR="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts"   # when the host supplies a plugin root
> ```
> If neither variable exists, resolve the plugin root from this loaded `skills/handoff/SKILL.md` location (two directories above its containing directory), and use its absolute `scripts` path. Do not assume the consumer project contains the scripts.
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
    "head_sha": "<git rev-parse HEAD, optional>", "diff_summary": "<optional>", "tests": [{"cmd": "...", "result": "pass"}],
    "commands": [], "decisions": [], "rejected_paths": [], "open_risks": []
  },
  "files_read_first": [{"path": "...", "why": "..."}],
  "files_skip": [{"path": "...", "why": "..."}]
}
```

Optional fields with nothing to say are **omitted**, never null/`"none"`. Unknown fields are rejected by the validator (catches typos). `mode` is `WRITE` or `RECOVER` for checkpoint JSON. Native BRIEF renders a task projection without checkpoint identity; external task Markdown is not validated as checkpoint JSON.

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

- Record the current commit as `state.head_sha`: `git rev-parse HEAD` (enables the READ-side "commits since brief written" drift signal). Omit only when not in a git repo.

From the session transcript, also note: tests run (pass/fail), commands that materially advanced the work, decisions that affect what the next session should do (not every decision — history belongs in the narrative), paths tried and rejected, open risks, the next concrete acceptance check.

### Step 3 — Render the brief

Use the schema above. Include the Resume prompt section with paste-and-go text matching the resolved key. Keep under 200 lines.

### Step 4 — Write to disk

Run `python3 "$SCR/handoff_paths.py" --init` and use its output as `<store>`. Build the typed object. Write it to a temp file and run `python3 "$SCR/handoff-validate.py" <tmp>.json`; fix every reported field and re-run until it prints `handoff-validate: OK`. Then move it to `<store>/<key>.json` (`<store>` from `"$SCR/handoff-dir.sh"`). Then prepend a narrative entry to `.claude/PROJECT_STATE.md` (unchanged — still markdown).

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

> **Auto-resume (hook-driven):** when `SessionStart-handoff-read.sh` is installed, a session opened via `/clear` or `/compact` (source `clear`/`compact`) gets the brief's five load-bearing fields — next step, done-when, next acceptance check, open risks, files-to-read-first — auto-rendered into context, so no explicit `/handoff resume` is needed. Other sources (`startup`/`resume`) get a one-line announce instead. Run `/catalyst:handoff resume` any time for the full READ render below.

1. Resolve `$SCR` (see Helper-script location), then `<store>` via `bash "$SCR/handoff-dir.sh"`. Run `python3 "$SCR/handoff-list.py" --json` to inventory canonical and legacy stores, including `HANDOFF.json`. For a duplicate key, the canonical file is the default; explicitly name the legacy path if the user wants that copy.
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

`handoff-render.py` now performs three automatic READ-time drift checks (all fail-open, all deterministic):

- **`!! MISSING: <path>`** — a `files_read_first` path no longer exists (absolute checked as-is; relative resolved against the recorded worktree root). Verify before resuming; the brief may point at moved/deleted files.
- **`!! STALE: brief written ~<age> ago …`** — the brief is older than `CATALYST_HANDOFF_STALE_HOURS` (default 24h). Diff current git state before resuming.
- **`- Commits since brief written: <N>`** (Summary block) — how far HEAD moved since WRITE, when the brief recorded `state.head_sha`. A diverged sha shows `Brief HEAD <sha> not in current history` instead.

Warning order: REPO MISMATCH > BRANCH MISMATCH > STALE > MISSING, then the resume body.

---

## Mode: RECOVER

The current session is degraded. Symptoms: agent forgets what it was doing, re-reads files, contradicts earlier decisions, repeats rejected approaches.

1. Determine key via the ladder (same as WRITE).
2. Read the existing brief via `handoff-render.py <key>` (canonical first, legacy fallback).
3. Read most recent 2-3 entries of `.claude/PROJECT_STATE.md`.
4. Run `git log --oneline -20` and `git diff` on the working branch.
5. Run `python3 "$SCR/handoff_paths.py" --init` and use its canonical store. Reconstruct the typed object from git/transcript, validate it (`python3 "$SCR/handoff-validate.py" <tmp>.json`), and write `<store>/<key>.json`. Preserve the old copy if recovering from legacy storage.
6. Do **not** prepend to PROJECT_STATE.md — recovery is re-assembly, not fresh signal.
7. Tell the user: "Recovery brief written at `<store>/<key>.json`. Run `/clear`, then paste this Resume prompt OR run `/catalyst:handoff resume`:" — and ALWAYS print the literal Resume prompt verbatim right below (the Resume prompt comes from `handoff-render.py` output — paste-and-go, not a pointer).

---

## Mode: REGROUND

The current session is still intact but recall is degrading — decisions slip into the low-recall "middle" of the context window, key acceptance checks are being re-derived instead of repeated verbatim, or files-to-keep are being re-read unnecessarily.

REGROUND is a **read-only mid-session re-injection**: it renders only the load-bearing fields of the brief (goal, locked decisions, files to keep in view) as a compact block, then returns. No disk write, no PROJECT_STATE update.

### When to use

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

Delegate the selected task while the originating session continues. “This” means the task just discussed; clarify only if its boundary is ambiguous. Route requests naming a subagent to native delivery, and requests naming a separate agent/session (for example Codex) to external delivery. No hook is needed. A request to prepare a brief only does not authorize dispatch.

### Prepare the task (both paths)

Extract objective, full agreed requirements, in/out of scope, relevant decisions and rejected paths, source files with reasons, dependencies, acceptance checks and expected return. Carry the selected conversation context that exists nowhere else; reference existing files instead of copying them. Do not include unrelated chat, secrets, or whole project history. Preserve requirements even when the task is long.

### Native subagent

1. Build the BRIEF object using `resume.done_when`, `resume.resume_by`, `state.next_acceptance_check`, relevant state lists and `files_read_first`. Omit checkpoint identity. Include `scope` and `return_instructions` strings: define allowed edits and require changed files, actual check results and unresolved issues on return. Include the working directory in the task instructions; do not assume it is inherited.
2. Render with `python3 "$SCR/handoff-render.py" --brief <tmp>.json`. The native limit is **30 lines** by default. The renderer preserves all supplied decisions and reports section counts on overflow. Shorten wording, reference a supporting artifact or decompose the task; never drop requirements to pass the cap.
3. For “handoff this to a subagent”, pass the rendered brief directly to the host's native agent-spawn tool. Select fresh/scoped context where supported. Use the host's workspace isolation for concurrent edits where available; if edits would overlap, arrange separation or sequence them before dispatch. Do not paste the whole conversation or narrative alongside the brief. If spawning is unavailable, report that and offer external delivery; do not claim dispatch occurred.
4. Track the native task using the host's result mechanism. Continue independent parent work when possible. On return, inspect the result and relevant evidence; report completed, partial or blocked work accurately. Integrate only within the user's authorized scope.

### External agent (file by default)

1. For Git coding tasks, offer **separate worktree + branch (recommended default)** or **current workspace**. Honor an existing selection; otherwise wait for the choice before finalizing workspace instructions. Do not treat silence as selection. For read-only/non-Git tasks use the identified directory. Record base commit, source worktree and any required uncommitted changes: a new worktree starts from a commit, not the parent's dirty files.
2. Read the bundled [task template](references/task-template.md) and fill it with the selected task. It must be executable without Catalyst installed. Keep every agreed requirement; **external files have no 30-line cap**. The task body specifies workspace setup, permitted actions, checks, completion ownership and integration boundaries. Leave `## Completion` empty for the recipient.
3. Run `python3 "$SCR/handoff_paths.py" --init --tasks`. Create a unique `<task-slug>-<unique-suffix>.md` under the returned directory using **exclusive creation** (Python `Path.open("x", encoding="utf-8")`, for example). Use a filename slug, never an unchecked path from chat. On collision choose another suffix; never overwrite. If initialization/write fails, report it; do not silently switch to inline. Keep the single task file in the main worktree so linked worktrees can access it.
4. Print only the location and a short copyable launch prompt, substituting the real absolute file path:

   > Read `<absolute-task-file>`. Execute its task, follow the workspace instructions, and update only its Completion section. Return a short prompt pointing to that section for the originating agent.

5. The receiving agent preserves everything before `## Completion`, records its status/checklist/evidence/integration instructions there and returns a small pointer message. No automatic cross-host notification, launch or merge. The user relays that message. The originating agent reads Completion, verifies the actual changes against the original checklist and reports readiness; completion text alone is not proof. The task file is a manually updated result, not a live status monitor.

**Explicit inline override:** only if the user asks for inline/full-message output, provide the complete task and return contract in the message. Do not create a task file or initialize storage for this path. The recipient returns a structured completion message instead. The workspace-choice rules still apply.

**Cross-machine use:** the user transfers the task file (and necessary artifacts). The recipient resolves the local repository and verifies the recorded base/dependencies; an inaccessible path is a blocker, not permission to invent missing context.

If a recipient needs narrative rationale, reference the exact PROJECT_STATE.md entry. BRIEF never writes or updates the narrative or a session checkpoint.

**Evaluator / reviewer briefs (anti-self-grade + pre-coding contract).** When the subagent's job is to grade or review an artifact:

- Dispatch it as a **separate Agent invocation with fresh context**. Give it the contract (`## Task` with `done_when` + acceptance check) and the artifact path only — never the generator's transcript, reasoning, or chat history. Self-evaluation bias is measured and severe.
- Agree "done" **before** the generator starts: the generator's brief states `done_when` and the acceptance check; the evaluator's brief quotes the same two lines verbatim. Neither side may redefine them mid-flight.
- One evaluator pass is enough for binary tasks (tests pass or fail). Iterate only on genuinely subjective output, and cap iterations explicitly in the brief.

---

## Store hygiene (`list` / `prune`)

The store accretes one brief per feature key. A merged branch leaves an orphan
brief behind, and an orphan whose branch name later recurs would be resolved by
tier 2 as if it were current.

```bash
python3 "$SCR/handoff-list.py"          # every brief: branch, liveness, age
python3 "$SCR/handoff-prune.py"         # propose orphans — deletes NOTHING
python3 "$SCR/handoff-prune.py" --apply # delete exactly what was proposed
```

A prune candidate is a brief whose recorded branch no longer exists locally
**and** which is older than 30 days. The current branch's brief and the legacy
`HANDOFF.json` slot are never candidates. Always show the user the dry-run list
and get confirmation before running `--apply` — this deletes state that a future
session may want.

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
- **BRIEF dumping PROJECT_STATE.md into a task.** Defeats task isolation.
- **External full brief in chat without an explicit inline request.** Default to a file and short pointer.
- **Overwriting a task file or editing its original checklist on completion.** Use exclusive creation; record results in Completion.
- **Assuming a worktree contains uncommitted parent changes.** Record and resolve dependencies first.
- **Native BRIEF over budget.** Reference supporting artifacts or re-decompose; never silently truncate. External task files have no 30-line cap.
- **Generator grading itself (self-evaluation bias).** An evaluator/reviewer brief MUST go to a separate Agent with fresh context, given the contract + artifact only (never the generator's transcript). See BRIEF.
- **Skipping the pre-coding contract.** Generator self-defines "done", evaluator grades a moving target. Put `done_when` + the acceptance check in both briefs before work starts.
- **Suggesting checkpoints for trivial sessions.** Explicit task-handoff requests still use BRIEF.

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

- **Pre-coding contract in BRIEF** assumes the generator can't self-define "done" rigorously enough.
- **Anti-self-grade in BRIEF** assumes self-evaluation bias is severe enough to require a separate fresh-context evaluator.
- **Native BRIEF's 30-line ceiling** assumes dispatch context should be compact; external files preserve longer requirements. Revisit the ceiling if artifact indirection costs more than it saves.
- **Manual external file transfer** assumes the user connects independent agent sessions. Revisit only if native cross-host task/result transport becomes available.
- **READ-time drift guards** (MISSING / STALE / commits-since) assume the model won't notice moved files or stale state on its own.
- **Retired 2026-09-02 (v0.7.0):** SPLIT and PIPELINE modes. Native Claude Code Agent/Workflow tooling absorbed the orchestration runtime; explicit-key WRITE covers session forking; the contract + anti-self-grade rules survived in BRIEF. Archived in the private planning repo.

> *"Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing."* — Anthropic

Review this skill annually (or when a new flagship model lands). Strip scaffolding that no longer earns its complexity. Document removals in PROJECT_STATE.md so the next reviewer knows what was tried and why it was retired.
