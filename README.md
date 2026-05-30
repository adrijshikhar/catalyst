<p align="center">
  <img src="assets/logo.svg" width="104" height="104" alt="Catalyst logo"/>
</p>

<h1 align="center">Catalyst</h1>

<p align="center">
  <strong>Harness engineering for Claude Code — skills that turn the model into a long-running, reliable system.</strong>
</p>

<p align="center">
  <a href="https://github.com/adrijshikhar/catalyst/releases"><img src="https://img.shields.io/github/v/release/adrijshikhar/catalyst?style=flat&color=blue" alt="Release"></a>
  <a href="https://github.com/adrijshikhar/catalyst/actions/workflows/ci.yml"><img src="https://github.com/adrijshikhar/catalyst/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/adrijshikhar/catalyst?style=flat" alt="License"></a>
  <a href="https://github.com/adrijshikhar/catalyst/stargazers"><img src="https://img.shields.io/github/stars/adrijshikhar/catalyst?style=flat&color=yellow" alt="Stars"></a>
  <a href="https://github.com/adrijshikhar/catalyst/commits/main"><img src="https://img.shields.io/github/last-commit/adrijshikhar/catalyst?style=flat" alt="Last commit"></a>
</p>

<p align="center">
  <a href="#how-it-works">How it works</a> •
  <a href="#what-a-handoff-looks-like">Demo</a> •
  <a href="#skills">Skills</a> •
  <a href="#install">Install</a> •
  <a href="#design-principles">Principles</a>
</p>

---

**Catalyst takes its name from chemistry.** A catalyst facilitates a reaction — makes it faster and more reliable — without being consumed by it.

This plugin is a catalyst for **human–AI collaboration**. It sits between you and Claude and smooths how you work together, then steps out of the way. In practice, it:

- **carries context across sessions** — so nothing gets re-explained after a `/compact`
- **blocks premature "it's done" claims** — no success without evidence
- **keeps subagents on-scope** — the right minimum context, no bleed
- **surfaces trouble before it compounds** — degradation and failure patterns, flagged early

Under the hood, Catalyst is grounded in **[harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps)** — the architectural patterns Anthropic itself uses to ship reliable agentic applications. It treats Claude not as a single chat but as a system that needs scaffolding for context resets, structured artifact handoffs, multi-agent orchestration, and explicit evaluator/generator separation.

Every component of every skill encodes an assumption about what the current model can't do reliably on its own. Those assumptions get stress-tested with each new flagship model — scaffolding that no longer earns its complexity gets stripped. The plugin grows opinionated about *when* to add complexity, not just *what* complexity to add.

## How it works

A long Claude session accumulates state that `/compact` quietly destroys: which decisions were made and why, which paths were tried and rejected, what "done" means, what the next concrete check is. Start a fresh session and that context is gone — you re-explain, or the model guesses.

Catalyst closes that gap. When you approach a context limit, end a session, or brief a subagent, the **`handoff`** skill writes a **strongly-typed JSON brief** — a small, schema-validated state packet — and prepends the *why* to a durable project narrative. The next session reads the brief back and resumes from exactly where you left off, no re-explanation. The same brief shape powers subagent task descriptions and pipeline-stage contracts, so one schema serves every boundary.

Around that core, the other skills make the harness *ambient*: lifecycle hooks fire the right `handoff` mode automatically, an evidence gate blocks premature "it works" claims, evaluator rubrics enforce generator≠evaluator separation, and end-of-session detectors surface failure patterns before they compound. The skills trigger themselves — you don't manage them.

## What a handoff looks like

WRITE produces a typed, validated brief (rejected if fields are missing or mistyped — that's the point):

```json
{
  "schema_version": "1",
  "key": "feat-jwt-expiry",
  "timestamp": "2026-05-30T10:00:00Z",
  "mode": "WRITE",
  "resume": { "done_when": "pnpm test auth.spec.ts 6/6",
              "resume_by": "re-read middleware, finish expiry check" },
  "state": {
    "branch": "feat/jwt-expiry",
    "next_acceptance_check": "expiry uses <= not <",
    "worktree": { "root": "/repo", "is_linked": false, "git_common_dir": "/repo/.git" },
    "tests": [{ "cmd": "pnpm test", "result": "fail" }]
  }
}
```

READ renders it back into a resume prompt the next session acts on directly — with guards that refuse to resume a brief from a different branch or repo:

```
# Resume — feat-jwt-expiry

## Resume prompt
> resume handoff 'feat-jwt-expiry': … next acceptance check: expiry uses <= not <.

## Summary
- Branch: feat/jwt-expiry
- Done when: pnpm test auth.spec.ts 6/6
- Next acceptance check: expiry uses <= not <
```

Briefs are stored once per feature key in the **main worktree** (`<main>/.claude/handoffs/<key>.json`), so every linked worktree shares one store keyed by branch — resume any feature from any worktree.

## Skills

| Skill | Purpose |
|-------|---------|
| [`handoff`](./skills/handoff/SKILL.md) | Structured context transfer for sessions, subagents, and pipelines. Four modes (WRITE / READ / RECOVER / BRIEF) plus PIPELINE orchestration. Typed JSON brief validated against a JSON Schema, feature-keyed via a three-tier ladder, centralized worktree-aware store, render-on-read resume, anti-self-grade guardrails. |
| [`verify-gate`](./skills/verify-gate/SKILL.md) | PreToolUse hook + skill that blocks "claim success" writes (test-results, build-status, deployment artifacts) unless the evidence file was Read first. Port of Anthropic's `verify-gate.sh` pattern. Solves optimistic completion bias. |
| [`hook-builder`](./skills/hook-builder/SKILL.md) | Pre-built lifecycle hooks (PreCompact / SessionStart / Stop / UserPromptSubmit) that wire `handoff` into the session lifecycle. Turns Catalyst from explicit to ambient. Plus an authoring helper for new hooks. |
| [`evaluator-library`](./skills/evaluator-library/SKILL.md) | 6 bundled domain rubrics (code-quality, ui-design, prose, security, performance, accessibility) dispatched via a shared brief builder that enforces anti-self-grade. Composes with handoff PIPELINE evaluator stages. |
| [`failure-pattern-detector`](./skills/failure-pattern-detector/SKILL.md) | Stop hook + skill that scans the session at end-of-session for 6 failure patterns (instruction-fade, edit-mismatch, stale-read, repeated-tool-call, recovery-spiral, context-drowning) and surfaces each with a specific recovery recipe. |
| [`pipeline-templates`](./skills/pipeline-templates/SKILL.md) | 3 bundled executable pipeline templates (audit-then-fix, research-plan-implement-review, parallel-review-synthesize) + `/pipeline run / list / save / --dry-run`. |
| [`brain-bridge`](./skills/brain-bridge/SKILL.md) | MCP adapter wrapper that pulls Company Brain context into handoff PIPELINE briefs as pointers — never inlined content. 3 bundled adapters. Configurable token budget + relevance threshold. |
| [`session-degradation-watch`](./skills/session-degradation-watch/SKILL.md) | UserPromptSubmit hook + skill that monitors 4 signals (context %, repeated tool call, stale read, contradiction with PROJECT_STATE) every turn and surfaces the most urgent alert. Composes additively with the orient hook. |

More skills land here as the harness matures. Roadmap focuses on patterns the Anthropic framework names: sprint contracts, GAN-style iterate loops, evaluator-generator separation, live application testing, context-budget watchers.

## What's in the harness

Catalyst maps directly to Anthropic's primitives:

| Anthropic primitive | Where Catalyst implements it |
|---------------------|------------------------------|
| Context resets > compaction | `handoff` WRITE/READ — fresh-agent bootstrap from `<main>/.claude/handoffs/<key>.json` |
| Structured artifact handoff (file-based, not conversational) | typed JSON brief schema, shared across all four modes |
| Specialized multi-agent (planner / generator / evaluator) | PIPELINE mode canonical role triad |
| Sprint contracts (pre-coding done agreement) | PIPELINE mode contract negotiation step |
| Anti-self-grade (separate evaluator subagent) | PIPELINE mode rule + `evaluator-library` dispatch guard |
| GAN-inspired iterate loops for subjective domains | PIPELINE mode optional loop pattern |
| Gradable rubrics for subjective domains | `evaluator-library` + eval-harness contracts at `skills/*/evals/` |
| Evidence-first writes (verify-gate.sh) | `verify-gate` skill |
| Lifecycle hooks (PreCompact / SessionStart / Stop / UserPromptSubmit) | `hook-builder` skill |
| Pre-built evaluator rubrics (code/ui/prose/security/perf/a11y) | `evaluator-library` skill |
| End-of-session failure-pattern surfacing | `failure-pattern-detector` skill |
| Executable saved pipeline templates | `pipeline-templates` skill |
| Brain / knowledge-layer context injection (MCP) | `brain-bridge` skill |
| Real-time degradation surfacing | `session-degradation-watch` skill |

## Install

Catalyst is its own one-plugin marketplace. From inside Claude Code:

```
/plugin marketplace add adrijshikhar/catalyst
/plugin install catalyst@catalyst
```

That registers the marketplace and installs the `catalyst` plugin. Skills become available immediately.

**Rollback:** every release is a git tag (`vX.Y.Z`). To pin or roll back, reinstall at that tag:

```
/plugin install catalyst@catalyst@<version>
```

Releases are listed at [github.com/adrijshikhar/catalyst/releases](https://github.com/adrijshikhar/catalyst/releases).

## Usage

After install, invoke skills explicitly or let Claude auto-trigger them:

- **Explicit:** `/handoff` to write a feature-keyed brief, `/handoff resume` to load one, `/pipeline` to orchestrate multi-stage work
- **Auto:** when you end a session, switch context, approach context limits, brief a subagent, or describe a multi-stage task, Claude triggers the right mode of `handoff`

Install the lifecycle hooks (`/hook-builder install --all`) to make all of this ambient — the hooks fire the right mode without you asking. See each skill's `SKILL.md` for full trigger conditions and behavior.

## Design principles

1. **One brief schema, many surfaces.** A session-handoff, a subagent task description, and a pipeline-stage contract are the same shape. Catalyst defines that shape once — and validates it.
2. **Context isolation is cheap; context bleed is expensive.** Briefs cap at 30 lines for subagents. Project narrative is referenced by pointer, never inlined.
3. **Generator ≠ evaluator.** Self-evaluation bias is measured and severe. Catalyst enforces separation as a primary anti-pattern in PIPELINE mode.
4. **Pre-coding sprint contracts.** Generator + evaluator negotiate "done" before any work happens. Acceptance checks are explicit, verifiable, and locked.
5. **Strip rather than accumulate.** Every primitive is a wager about a model limitation. Review yearly; retire what flagship models grow past.

## Why "Catalyst"

The name says what it does: a catalyst facilitates a process without becoming part of the product. These skills facilitate the work between you and Claude — they activate when needed, smooth the handoff, then step out of the way without crowding the main context.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Skill proposals welcome via GitHub issues using the `new-skill` template. Proposals should ground themselves in a specific harness-engineering pattern from the [Anthropic article](https://www.anthropic.com/engineering/harness-design-long-running-apps) or call out the model-limitation assumption they encode.

## References

- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic's framework that grounds Catalyst's design
- [Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents.md) — the context-isolation primitives Catalyst builds on

## License

MIT — see [LICENSE](./LICENSE).
