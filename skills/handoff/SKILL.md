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
| `.claude/handoffs/<key>.md` (or `.claude/HANDOFF.md` in legacy mode) | **Ephemeral brief** — minimum payload to resume. Points at durable artifacts. | Overwritten on every WRITE for that key. | At the start of the next session for that key. |
| `.claude/PROJECT_STATE.md` | **Persistent narrative** — accreting log of decisions, why, rejected paths, surprises. Project memory. | Prepended forever (newest first). Repo-level — single file. | On demand only — when a brief points the agent at it. |

The brief survives one session boundary per key. The narrative survives the project. PROJECT_STATE.md is intentionally NOT split per feature — cross-feature decisions matter for future features and must be co-located.

## Feature key resolution

WRITE / READ / RECOVER determine the **key** for the brief in this order:

| Priority | Source | Resolved path | When |
|----------|--------|---------------|------|
| 1 | User passes `/handoff <name>` or says "handoff for <feature>" | `.claude/handoffs/<name>.md` | Explicit override. Feature spans branches, branch name is garbage, or parallel spikes need separate slots. |
| 2 | `git branch --show-current` (sanitized: `/` → `-`, length-cap 80, special chars dropped) | `.claude/handoffs/<branch>.md` | Default. Branch = feature in modern git flow. Zero ceremony. |
| 3 | Not in a git repo, or detached HEAD | `.claude/HANDOFF.md` | Legacy single-slot fallback. Backwards compatible with v0.2. |

**Sticky session key:** once a WRITE picks a key, subsequent WRITEs / RECOVERs in the same session use the same key. If the user switches branches mid-session, surface the change: "Branch switched. Future handoffs will target `<new-key>.md`. Confirm?"

BRIEF and PIPELINE modes do not persist, so they don't resolve a key — they may *reference* a key when telling a subagent which feature's narrative slice is relevant.

## Four modes (overview)

| Mode | Trigger | Persists? | Consumer |
|------|---------|-----------|----------|
| **WRITE** | Ending session, hitting context limit, before `/clear` or `/compact`, end of pipeline stage, user says "handoff" / `/handoff` | Disk: `.claude/handoffs/<key>.md` + prepend `PROJECT_STATE.md` | Next session |
| **READ** | Fresh session with brief(s) present, user wants to resume | None (loads into current context) | Current session |
| **RECOVER** | Context degraded mid-session — re-reads, contradictions, forgotten decisions | Disk: overwrites brief for current key; does NOT prepend narrative | Current session, post-`/clear` |
| **BRIEF** | About to dispatch a subagent and want it to start with the right minimum context | In-memory string passed to Agent tool task description; no disk | Subagent |

The schema for the brief is shared across all four modes. Only persistence and consumer differ.

Plus **PIPELINE** mode — orchestration built on top of BRIEF (decompose → route → dispatch → synthesize). See its own section below.

Do NOT invoke for trivial sessions or one-step subtasks. Three-turn debug doesn't need a handoff. A rename across one file doesn't need a pipeline. Use judgement — if there's nothing a future consumer would lose, skip the skill.

---

## Brief schema (shared)

Every brief follows this shape. Fields that have nothing to say are omitted, not filled with "none" — an absent field is cleaner than a noise field.

```markdown
# Handoff — <ISO timestamp>
# Key: <resolved-key>          (omit in BRIEF mode — subagents don't persist by key)

## Resume prompt                (include in WRITE/READ/RECOVER; omit in BRIEF)
> read .claude/handoffs/<key>.md and continue. next acceptance check: <quoted>.

## Re-entry instructions        (in BRIEF mode this becomes "## Task")
- Resume by: <one sentence>.
- Done when: <one verifiable acceptance check>.
- Read `.claude/PROJECT_STATE.md` ONLY if you need historical context.

## State packet
- **Branch:** <branch-name>
- **Diff summary:** <e.g., "3 files, +120/-45 in src/auth/">
- **Tests run:** <list with pass/fail>
- **Commands that mattered:** <short list>
- **Decisions affecting next session:** <bullets — what's locked in>
- **Rejected paths:** <bullets — don't redo>
- **Open risks:** <bullets>
- **Next acceptance check:** <one concrete check>

## Files to read first
- <path1> — <why>

## Files to NOT load by default
- <path> — <why safe to skip>
```

The **Resume prompt** is a single-line directive a fresh session can paste verbatim. For tier-3 (legacy) handoffs, it reads `read .claude/HANDOFF.md and continue. next acceptance check: <quoted>`. For BRIEF mode (subagent), there is no Resume prompt — the brief itself IS the task description.

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
```

From the session transcript, also note: tests run (pass/fail), commands that materially advanced the work, decisions that affect what the next session should do (not every decision — history belongs in the narrative), paths tried and rejected, open risks, the next concrete acceptance check.

### Step 3 — Render the brief

Use the schema above. Include the Resume prompt section with paste-and-go text matching the resolved key. Keep under 200 lines.

### Step 4 — Write to disk

Write the brief to `.claude/handoffs/<key>.md` (or `.claude/HANDOFF.md` for tier 3). Then prepend a new entry to `.claude/PROJECT_STATE.md` (create the file with its header if it doesn't exist). Entry title includes the feature key: `## <ISO date> — [<key>] <short title>`.

If `PROJECT_STATE.md` doesn't exist, create with this header:

```markdown
# Project state — narrative log

Accretes over the life of the project. Each handoff prepends a new dated section above earlier entries.
Read sections selectively. The brief at `.claude/handoffs/<key>.md` is the entry point; this file is the reference.
```

Prepend (NOT append) above any existing entries:

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
  .claude/handoffs/<key>.md  (<n> lines)
  .claude/PROJECT_STATE.md   (+<n> lines prepended)

Next session — paste this Resume prompt OR run `/catalyst:handoff resume`:

> read .claude/handoffs/<key>.md and continue. next acceptance check: <one-line check verbatim from the brief>.
```

Both options work. The slash command (`/catalyst:handoff resume`) is faster if the user is in a Catalyst-enabled session; the literal paste works in any Claude Code session even before plugins load.

---

## Mode: READ

A new session has loaded with one or more briefs present, and the user wants to resume.

1. Look for `.claude/handoffs/`. If empty / missing, fall back to legacy `.claude/HANDOFF.md`.
2. If multiple briefs exist:
   - Detect current branch.
   - Surface ALL briefs. If one matches the current branch (tier-2 match), name it as the primary suggestion.
   - List the others with mtime + first non-header line as preview.
   - Wait for the user to confirm. Do NOT silently choose.
3. Read the selected brief end to end.
4. Read files listed under "Files to read first" — load-bearing.
5. Do **not** read `.claude/PROJECT_STATE.md` by default. Open it only when the brief explicitly says to, or you hit a decision whose rationale you need.
6. Confirm: "Resumed from `<key>`. Next acceptance check: <quote from brief>. Starting now."
7. The selected key becomes the sticky session key.

If the brief's timestamp is more than ~24h old, diff against current git state before resuming — the working tree may have moved.

For legacy v0.2-shaped briefs (no `# Key:` line, no Resume prompt section), READ still works — those fields are optional on input.

---

## Mode: RECOVER

The current session is degraded. Symptoms: agent forgets what it was doing, re-reads files, contradicts earlier decisions, repeats rejected approaches.

1. Determine key via the ladder (same as WRITE).
2. Read existing brief at the resolved path if any.
3. Read most recent 2-3 entries of `.claude/PROJECT_STATE.md`.
4. Run `git log --oneline -20` and `git diff` on the working branch.
5. Reconstruct a fresh brief from those sources using the schema above. Overwrite the file at the resolved key.
6. Do **not** prepend to PROJECT_STATE.md — recovery is re-assembly, not fresh signal.
7. Tell the user: "Recovery brief written at `<resolved-path>`. Run `/clear`, then paste this Resume prompt OR run `/catalyst:handoff resume`:" — and ALWAYS print the literal Resume prompt verbatim right below (same shape as WRITE Step 5 — paste-and-go, not a pointer).

---

## Mode: BRIEF

You're about to dispatch a subagent for a bounded subtask. The subagent needs the minimum context that makes its job possible — no more.

1. Identify the subtask. Make it concrete.
2. Filter the state packet to fields relevant to that subtask. Drop fields with nothing useful to add (no "none" placeholders).
3. Render the brief inline. Use the same schema, but:
   - Omit the `# Key:` line (BRIEF doesn't persist).
   - Omit the `## Resume prompt` section (the brief IS the prompt).
   - The `## Re-entry instructions` section becomes `## Task` (named for the subagent's perspective).
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
.claude/
├── HANDOFF.md                 # legacy / no-git fallback (tier 3)
├── PROJECT_STATE.md           # repo-level narrative
├── handoffs/                  # per-feature briefs (tiers 1 + 2)
│   ├── feat-jwt-expiry.md
│   └── refactor-auth-middleware.md
└── pipelines/                 # saved pipeline templates
    └── audit-then-plan.md
```

All four are gitignored by default. Commit them if the team wants shared state.

---

## Migration from v0.2

No automatic migration. Backwards compatible:

- v0.2's `.claude/HANDOFF.md` keeps working under tier 3 if no `.claude/handoffs/` dir exists.
- First v0.3 WRITE lands on a tiered path; legacy file left untouched.
- READ surfaces both legacy and feature briefs when present, with legacy flagged as such.
- User can manually `mv .claude/HANDOFF.md .claude/handoffs/<feature>.md` to upgrade.

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

**Bad** (vague):

```markdown
# Handoff
We worked on auth. Some tests failing. Continue tomorrow.
```

**Good** (state packet, immediately actionable):

```markdown
# Handoff — 2026-05-24T01:42:00Z
# Key: feat-jwt-expiry

## Resume prompt
> read .claude/handoffs/feat-jwt-expiry.md and continue. next acceptance check: pnpm test src/auth/auth.spec.ts passes 6/6.

## Re-entry instructions
- Resume by: fixing the JWT expiry check in src/auth/middleware.ts (add leeway parameter).
- Done when: src/auth/auth.spec.ts:42-78 all pass.

## State packet
- **Branch:** feat/jwt-expiry
- **Diff summary:** 2 files, +18/-6 in src/auth/
- **Tests run:** src/auth/auth.spec.ts — 4 of 6 pass; expiry tests fail
- **Decisions affecting next session:**
  - Use `Date.now()` (UTC ms) — not `new Date()` (alloc in hot path)
  - JWT lib is `jose`, not `jsonwebtoken` (see PROJECT_STATE.md `## 2026-05-20 — [feat-jwt-expiry] JWT library migration`)
  - Operator is `<=` not `<`
- **Rejected paths:** `<` (off-by-one); `new Date()` (alloc).
- **Open risks:** Clock skew not addressed yet.
- **Next acceptance check:** `pnpm test src/auth/auth.spec.ts` passes 6/6.

## Files to read first
- src/auth/middleware.ts — file under repair
- src/auth/auth.spec.ts:42-78 — failing tests

## Files to NOT load by default
- src/auth/types.ts — stable
- src/users/* — unrelated
- PROJECT_STATE.md — historical only; brief above names the binding decisions
```

The good version answers "what do I do first, what is success, what should I not redo" in under 30 lines.

---

## Model evolution

Every component of this skill encodes an assumption about what the current model can't do reliably alone:

- **Sprint contracts** assume the generator can't self-define "done" rigorously enough.
- **Canonical role triad** assumes single-context multi-step work degrades.
- **GAN loop** assumes the generator can't self-improve subjective output.
- **BRIEF mode's 30-line ceiling** assumes context bleed is severe enough to require a hard cap.

> *"Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing."* — Anthropic

Review this skill annually (or when a new flagship model lands). Strip scaffolding that no longer earns its complexity. Document removals in PROJECT_STATE.md so the next reviewer knows what was tried and why it was retired.
