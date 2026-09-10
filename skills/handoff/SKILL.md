---
name: handoff
description: Use when handing a task to a native subagent or an external agent, ending a session, switching context, approaching compaction, resuming a prior handoff, or recovering degraded context. Five modes — WRITE saves a session checkpoint, READ resumes it, RECOVER rebuilds it, REGROUND re-injects its essentials, and BRIEF delegates a selected task with an explicit completion contract. BRIEF dispatches native subagents directly; external agents receive a self-contained task file and short launch prompt by default, with inline output only on explicit request. Trigger phrases include "handoff this to a subagent", "handoff this to Codex", "handoff this to <any agent>", "brief a subagent", "prepare a brief for <agent>", "inline handoff brief", "handoff", "resume", and "reground". Writing a task brief for another agent by hand, without this skill, drops the acceptance checklist and return contract the recipient needs. Any request to hand a task to another agent goes through this skill even when that agent's CLI is installed — never run the other agent directly. Use this skill liberally for decisions worth preserving and isolated tasks worth delegating.
---

# Handoff

A handoff is a **state packet** the next session or subagent can act on without re-explanation. `/compact` loses the details that matter; subagent task descriptions either over-share (context bleed) or under-share (questions the subagent cannot ask). A handoff keeps only what matters, in the structure the consumer needs. Patterns follow Anthropic's [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps): context resets over compaction, structured artifact handoffs, pre-coding contracts, generator ≠ evaluator.

## Two files per checkpoint

| File | Purpose | Lifetime | Loaded |
|------|---------|----------|--------|
| `<store>/<key>.json` (legacy slot `<store>/HANDOFF.json`) | **Ephemeral brief** — minimum payload to resume; points at durable artifacts | Overwritten on every WRITE for that key | Start of the next session for that key |
| `<main>/.catalyst/PROJECT_STATE.md` | **Persistent narrative** — decisions, why, rejected paths, surprises | Prepended forever, newest first; one file per repo, never split per feature | On demand, when a brief points at it |

## Feature key resolution

| Priority | Source | Path | When |
|----------|--------|------|------|
| 1 | `/handoff <name>` | `<store>/<name>.json` | Explicit override |
| 2 | `git branch --show-current` (sanitized `/`→`-`, cap 80) | `<store>/<branch>.json` | Default |
| 3 | Not in a git repo, or detached HEAD | `<store>/HANDOFF.json` | Legacy single-slot fallback |

`<store>` is `<main>/.catalyst/handoffs/` where `<main>` is the main worktree (parent of `git rev-parse --git-common-dir`; the current directory outside Git). Print it with `bash "$SCR/handoff-dir.sh"` or `python3 "$SCR/handoff_paths.py"`. Every linked worktree shares one store keyed by branch. Detect "in a repo?" with `git rev-parse --git-dir`, never `[ -d .git ]`. Everything Catalyst writes lives under `<main>/.catalyst/`: briefs in `handoffs/`, task files in `tasks/`, the narrative `PROJECT_STATE.md`, knobs in `config.json`. Nothing new is written under `.claude/`. Legacy locations (`.claude/handoffs/<key>.json`, `.claude/PROJECT_STATE.md`, `.claude/catalyst.json`) are read when the canonical file is absent; old files are never moved or deleted, and inventory lists both locations.

**Before any write:** `python3 "$SCR/handoff_paths.py" --init` (add `--tasks` for task files). It creates only the selected store and, in Git, ensures `.catalyst/` is in the main worktree's `.gitignore`. If it fails, stop and report. READ, REGROUND, `list` and the hooks are read-only.

**Sticky session key:** the first WRITE's key is reused by later WRITE/RECOVER calls in the session. If the branch changes, surface it: "Branch switched. Future handoffs will target `<new-key>.json`. Confirm?" BRIEF uses a task name, never the sticky key, and never writes a checkpoint or the narrative.

## Five modes

| Mode | Trigger | Persists? | Consumer |
|------|---------|-----------|----------|
| **WRITE** | Ending a session, context limit, before `/clear` or `/compact`, "handoff" / `/handoff` | `<store>/<key>.json` (validated) + prepend `.catalyst/PROJECT_STATE.md` | Next session |
| **READ** | Fresh session with brief(s) present, user wants to resume | None | Current session |
| **RECOVER** | Context degraded mid-session — re-reads, contradictions, forgotten decisions | Overwrites the brief; no narrative entry | Current session, post-`/clear` |
| **REGROUND** | Recall drifting mid-session | None (read-only re-injection) | Current session |
| **BRIEF** | Delegate a selected task to a subagent or external agent | Native: tool argument. External: task file by default | Task recipient |

To fork a braided session, WRITE once per thread with explicit keys: `/catalyst:handoff <key-a>`, then `/catalyst:handoff <key-b>`. Skip automatic checkpoint suggestions for trivial sessions; always honor an explicit task-handoff request, however small.

## Brief schema and helper scripts

The brief is typed JSON validated against the bundled `brief.schema.json`: `schema_version` `"1"`, `key`, `timestamp` (shell-provided ISO-8601 `Z`), `mode` (`WRITE` | `RECOVER`), `resume` {`done_when`, `resume_by`, optional `prompt`, `history_pointer`}, `state` {`branch`, `next_acceptance_check`, `worktree` {`root`, `is_linked`, `git_common_dir`}, optional `head_sha`, `diff_summary`, `tests`, `commands`, `decisions`, `rejected_paths`, `open_risks`}, `files_read_first` and `files_skip` (lists of {`path`, `why`}). Optional fields with nothing to say are omitted, never null or `"none"`; unknown fields are rejected. A worked example is in [references/example-brief.md](references/example-brief.md).

> **Helper-script location (read this first).** The scripts (`handoff-dir.sh`, `handoff-validate.py`, `handoff-render.py`, `handoff_paths.py`, `handoff-list.py`, `handoff-prune.py`) ship **inside the plugin**, NOT in the user's project. Resolve them once per mode and reuse `$SCR`:
> ```bash
> SCR="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts"   # when the host supplies a plugin root
> ```
> If neither variable exists, resolve the plugin root from this loaded `skills/handoff/SKILL.md` (two directories above its directory) and use its absolute `scripts` path. NEVER write a bare relative `scripts/handoff-render.py` into a resume prompt or run it from the user's repo — it does not exist there. The durable resume entry point is the slash command **`/catalyst:handoff resume`**, which re-enters this skill and resolves `$SCR` again.

---

## Mode: WRITE

1. **Key** — apply the ladder; sticky within the session.
2. **Gather state** — run in parallel where supported: `git branch --show-current`, `git status --short`, `git diff --stat`, `git log --oneline -10`, `git rev-parse HEAD` (→ `state.head_sha`), and `git rev-parse --path-format=absolute --git-common-dir` (→ `state.worktree.git_common_dir`; never `--absolute-git-dir`, which returns the worktree-private dir in a linked worktree and fires a false `REPO MISMATCH`). From the transcript note tests run, commands that advanced the work, decisions the next session depends on, rejected paths, open risks and the next concrete acceptance check.
3. **Build and validate** — write the typed object to a temp file, run `python3 "$SCR/handoff-validate.py" <tmp>.json`, fix every reported field until it prints `handoff-validate: OK`, then move it to `<store>/<key>.json` (store from `handoff_paths.py --init`).
4. **Narrative** — prepend an entry to `<main>/.catalyst/PROJECT_STATE.md`, directly below the header and above earlier entries. Create the header first if the file is new, and verify the first line is still `# Project state` afterwards. If a legacy `.claude/PROJECT_STATE.md` exists and the canonical file does not, create the canonical file with the header plus one line `Earlier entries: .claude/PROJECT_STATE.md` — do not move or edit the legacy file.

```markdown
# Project state — narrative log

Accretes over the life of the project. Each handoff prepends a new dated section above earlier entries.
Read sections selectively. The brief at `<store>/<key>.json` is the entry point; this file is the reference.
```

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
  .catalyst/PROJECT_STATE.md (+<n> lines prepended)

Next session — run `/catalyst:handoff resume` (or paste the Resume prompt):

> resume handoff '<key>': run `/catalyst:handoff resume` (READ mode), then continue. next acceptance check: <one-line check verbatim from the brief>.
```

The resume prompt MUST route through `/catalyst:handoff resume` — never a bare `python3 scripts/handoff-render.py <key>`. The helper scripts live in the plugin, not the user's project, so a relative script path fails everywhere except the Catalyst repo itself. The slash command re-enters this skill, which resolves `$SCR` and renders the brief.

---

## Mode: READ

> **Auto-resume (hook-driven):** a session opened via `/clear` or `/compact` gets the brief's load-bearing fields auto-rendered by `SessionStart-handoff-read.sh`; `startup`/`resume` get a one-line announce. `/catalyst:handoff resume` gives the full render any time.

1. Resolve `$SCR`, then inventory with `python3 "$SCR/handoff-list.py" --json` (canonical + legacy stores, including `HANDOFF.json`). For a duplicate key the canonical file wins unless the user names the legacy path.
2. Multiple briefs: surface ALL of them, name the current-branch match as the primary suggestion, list the others with mtime + key, and wait for the user. Never silently choose.
3. `python3 "$SCR/handoff-render.py" <key>` and follow its output. Heed every `!!` line before continuing, in the order printed: `REPO MISMATCH` > `BRANCH MISMATCH` > `STALE` > `MISSING`, plus `Commits since brief written: N`. If the brief was written in another (linked) worktree, say so and offer to `cd` there rather than resuming in the wrong tree.
4. Read `files_read_first`. Do **not** read `PROJECT_STATE.md` (canonical `.catalyst/`, legacy `.claude/`) unless the brief says to or you need a decision's rationale.
5. Confirm: "Resumed from `<key>`. Next acceptance check: <quote from brief>. Starting now." The key becomes the sticky session key.

---

## Mode: RECOVER

The session is degraded: forgotten goals, re-reads, contradicted decisions, repeated rejected approaches.

1. Key via the ladder. Render the existing brief (`handoff-render.py <key>`; canonical first, legacy fallback) and read the 2–3 newest `PROJECT_STATE.md` entries (`.catalyst/` first, then legacy `.claude/`).
2. `git log --oneline -20` and `git diff` on the working branch.
3. `handoff_paths.py --init`, rebuild the typed object from git + transcript, validate, write `<store>/<key>.json`. Keep the old copy when recovering from legacy storage.
4. Do **not** prepend to `PROJECT_STATE.md` — recovery is re-assembly, not fresh signal.
5. Say: "Recovery brief written at `<store>/<key>.json`. Run `/clear`, then paste this Resume prompt OR run `/catalyst:handoff resume`:" and print the renderer's Resume prompt verbatim beneath it.

---

## Mode: REGROUND

Read-only mid-session re-injection for when recall is drifting: a file you have notes on gets re-read, a decision is re-litigated without new information, the acceptance check is being re-derived instead of repeated verbatim.

```bash
python3 "$SCR/handoff-render.py" --reground <key>            # or --reground --file <path>
```

It prints only the goal (`done_when` + `next_acceptance_check`), the first five locked decisions and `files_read_first` with reasons — no mismatch checks, no rejected paths, no resume prompt, no disk write. Read the block into the working context and continue.

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

**Explicit inline override:** only if the user asks for inline/full-message output, provide the complete task and return contract in the message, using the task template's `## Task`, `## Workspace`, `## Acceptance checklist` and `## Return instructions` headings. Do not create a task file or initialize storage for this path. The recipient returns a structured completion message instead. The workspace-choice rules still apply. Inline is a message the user relays: never launch, probe or install the other agent's CLI (`codex exec`, `agy`, and so on), never dispatch a native subagent in its place, and never run the task yourself — Catalyst prepares the brief; the user delivers it.

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

- **Inlining file contents or the README into a brief.** Point at paths and line ranges.
- **Writing only one of brief / narrative on WRITE.** Both or neither (RECOVER writes only the brief).
- **Skipping rejected paths.** Highest-ROI field: the next agent will otherwise redo them.
- **Vague next check.** "Continue the work" is not verifiable; "`pnpm test src/auth/` shows `auth.spec.ts` green" is.
- **Reading the whole narrative on resume, or auto-loading every brief.** The brief is the entry point; always select one.
- **Silent key-switching, or tier 3 when tiers 1–2 are available.**
- **BRIEF dumping PROJECT_STATE.md into a task, or a full external brief in chat without an explicit inline request.**
- **Native BRIEF over the 30-line budget.** Reference supporting artifacts or re-decompose; never silently truncate.
- **Generator grading itself, or no pre-coding contract.** Fresh-context evaluator, `done_when` + acceptance check fixed in both briefs before work starts.

**Bad** next check: `"notes": "worked on auth, some tests failing, continue tomorrow"`.
**Good**: `"next_acceptance_check": "pnpm test src/auth/auth.spec.ts passes 6/6"` with `rejected_paths: ["< operator (off-by-one)", "new Date() (alloc)"]` — first action, success criterion and what not to redo, all validated before they reach disk.

---

## Model evolution

Each component encodes an assumption about what the current model cannot do reliably alone: the pre-coding contract (self-defining "done"), anti-self-grade (self-evaluation bias), the native 30-line ceiling (compact dispatch context), manual external file transfer (no cross-host task transport yet), READ-time drift guards (moved files and stale state go unnoticed). SPLIT and PIPELINE were retired 2026-09-02 once native agent tooling absorbed orchestration.

> *"Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing."* — Anthropic

Review annually or when a new flagship model lands; strip scaffolding that no longer earns its complexity and record removals in PROJECT_STATE.md.
