# Catalyst — principles & strict rules

The foundation model for the plugin. Every feature, hook, skill, and change is validated against this document. When a change conflicts with a principle here, the change is wrong until either the change or this document is deliberately revised.

Grounded in [harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps). This file is the *why* and the *non-negotiables*; [CLAUDE.md](../CLAUDE.md) holds the mechanical contributor conventions; [docs/HARNESS.md](./HARNESS.md) maps each skill to a primitive.

---

## Identity

Catalyst is a **catalyst for human–AI collaboration**: it sits between the human and Claude, makes the work faster and more reliable, then steps out of the way without being consumed by it. It treats Claude not as a chat but as a long-running system that needs scaffolding for context resets, structured handoffs, multi-agent orchestration, and evaluator/generator separation.

It is **not**: a chat wrapper, a memory database, an autonomous-loop runner, a generic harness scaffolder, or a Company-Brain competitor. When a feature drifts toward those, it is out of scope (see CLAUDE.md "What Catalyst will NOT build").

---

## Core principles (the durable *why*)

Each is a wager about a current model limitation. They are reviewed, not eternal.

1. **Collaboration first — facilitate, then step out.** A feature exists to smooth the work between human and Claude, then get out of the context. If it crowds the main context or demands management, it is failing its purpose.

2. **Never lie to the user. A false signal is worse than no signal.** A diagnostic that reports a wrong number, a stale state, or a per-turn nag trains the user to ignore the entire plugin. Correctness of what we surface outranks how much we surface. If we cannot compute a signal trustworthily, we suppress it — we do not guess.

3. **Ground in real behavior, not assumed behavior.** Read the real transcript shape, the real config, the real tool output — never a convenient assumption. Fixtures and tests MUST match what production actually produces; a green test against a fictional schema is a liability, not a safeguard.

4. **Strip rather than accumulate.** Every primitive is a wager about what the model can't do reliably alone. Each new feature must name the limitation it bets on and how it will be reviewed. Signals/skills that flagship models grow past are *retired*, not carried — "broken" is never automatically "must fix"; "fix vs retire" is a real decision.

5. **One schema / one reader, many surfaces.** A session handoff, a subagent brief, and a pipeline-stage contract are the same shape — defined once, validated once. Load-bearing parsing/coupling lives in one tested place so a change is a one-file fix, not a scattered hunt.

6. **Context isolation is cheap; context bleed is expensive.** Briefs carry the minimum viable context. Project narrative is referenced by pointer (file:line, ADR id, doc tag), never inlined. Subagents get exactly what they need and nothing more.

7. **Generator ≠ evaluator.** Self-evaluation bias is real and severe. Any grading/review step uses a fresh-context evaluator that never saw how the artifact was produced. Anti-self-grade is a hard rule, not a preference.

8. **Suggest, never auto-act.** Hooks and detectors advise; they never auto-recover, auto-commit, or mutate state on the agent's behalf. In-loop auto-recovery does not work — the recipe names the next step; acting on it is the agent's (or human's) choice.

9. **Fail open.** A hook or helper that hits an infrastructure error (missing `jq`, missing file, unparseable input) must degrade to inert and let the user proceed — never block the session on Catalyst's own failure. Silent fail-open that hides lost protection is itself a bug: surface it once.

10. **Determinism at the leaf.** Every graded assertion bottoms out in `exists` / `contains` / byte-equality — never model narration. Evals are written before the implementation they grade (EDD), and a new assertion must fail (red) against the bug before the fix turns it green.

---

## Strict rules (the enforceable *what*)

MUST / NEVER. A change that violates one of these is blocked until fixed.

### Hooks
- MUST be POSIX `bash` + `jq` only. No Python or other runtime deps in hooks (portability).
- MUST start with `set -euo pipefail` and MUST fail open on infra error.
- MUST emit only JSON keys valid for their event. PreCompact / Stop use top-level `systemMessage` — NEVER `hookSpecificOutput` (it fails schema validation). PreToolUse uses `hookSpecificOutput.permissionDecision`; UserPromptSubmit/PostToolUse/SessionStart use `hookSpecificOutput.additionalContext`.
- MUST resolve plugin assets via `${CLAUDE_PLUGIN_ROOT}` and project files via `${CLAUDE_PROJECT_DIR}`. NEVER write outside the project dir except `/tmp`.
- MUST read the transcript through the shared reader (real `.message.content[]` shape) — NEVER hand-roll a top-level `select(.type==...)`.
- NEVER auto-recover or mutate state. Suggest only.

### Skills & commands
- Every `skills/<name>/SKILL.md` MUST have YAML frontmatter with `name` + `description`; the description leads with trigger contexts. Body ≤ ~500 lines.
- A skill encoding an assumption about model limits MUST carry a "Model evolution" section.
- Commands are thin wrappers; the logic lives in the skill.

### Eval-driven development
- Evals/tests land BEFORE the implementation they grade (`test(<scope>):` commits before `feat(<scope>):`).
- Fixtures MUST match the real production schema. A new matcher ships with a fixture that fails red first.
- Assertions are deterministic at the leaf.

### Security & hygiene
- NEVER commit secrets, tokens, or personal absolute paths (`/Users/<name>`, …). Lint enforces.
- Validate input at boundaries; never trust external data.

### Process
- Non-trivial work follows spec → plan → implementation; trivial fixes may skip.
- One logical change per commit; conventional commits with mandatory scope when feature-specific; em-dash headline style; NEVER add `Co-Authored-By`.
- All changes reach `main` via PR through the CI gate. NEVER hand-write `chore: bump version` — the auto-release pipeline owns version bumps. Minor/major bumps: hand-edit `plugin.json` before the triggering push.
- Repo-internal conventions belong in CLAUDE.md, NEVER shipped as a skill to plugin users.

---

## Change-validation checklist

Run this against every feature/change before it merges. Each item maps to a principle/rule above.

- [ ] **Purpose** — does it facilitate human↔Claude collaboration, or add management burden? (P1)
- [ ] **Truthfulness** — does any surfaced signal/number/state reflect reality, with suppression (not guessing) when uncertain? (P2)
- [ ] **Real grounding** — tested against real production shapes; fixtures match production? (P3)
- [ ] **Earns its place** — names the model limitation it wagers on; considered fix-vs-retire for anything broken/inert? (P4)
- [ ] **DRY load-bearing parsing** — reuses the shared schema/reader rather than a new ad-hoc parse? (P5)
- [ ] **No context bleed** — pointers not inlined; minimum viable context? (P6)
- [ ] **Anti-self-grade** — any evaluation uses a fresh, transcript-blind evaluator? (P7)
- [ ] **Suggest-only** — no auto-recovery / state mutation on the agent's behalf? (P8)
- [ ] **Fail-open** — infra errors degrade to inert + surfaced, never block? (P9)
- [ ] **EDD + determinism** — evals first, failed red, leaf-level assertions? (P10)
- [ ] **Rules** — hooks/skills/security/process strict rules all satisfied?

If any box is unchecked, the change is not ready.

---

## Precedence

1. **The user's explicit instruction** wins over everything.
2. **These principles** override default model behavior and convenience.
3. When two principles conflict, **"never lie to the user" (P2) and "fail open" (P9) win** over completeness — it is always better to surface less, correctly, than more, wrongly.

---

## Model evolution

This document encodes wagers about today's models. Review it at every flagship-model landing and at least annually. Strip principles/rules that no longer earn their complexity; retire skills/signals a smarter model makes redundant. Principles are observations, not commandments — but until deliberately revised here, they are binding.
