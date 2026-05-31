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
  <a href="./docs/HARNESS.md">Deep dive</a>
</p>

---

**Catalyst takes its name from chemistry.** A catalyst facilitates a reaction — makes it faster and more reliable — without being consumed by it.

This plugin is a catalyst for **human–AI collaboration**. It sits between you and Claude and smooths how you work together, then steps out of the way. In practice, it:

- **carries context across sessions** — so nothing gets re-explained after a `/compact`
- **blocks premature "it's done" claims** — no success without evidence
- **keeps subagents on-scope** — the right minimum context, no bleed
- **surfaces trouble before it compounds** — degradation and failure patterns, flagged early

Under the hood, Catalyst is grounded in **[harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps)** — the architectural patterns Anthropic itself uses to ship reliable agentic applications. It treats Claude not as a single chat but as a system that needs scaffolding for context resets, structured artifact handoffs, multi-agent orchestration, and explicit evaluator/generator separation.

## How it works

A long Claude session accumulates state that `/compact` quietly destroys: which decisions were made and why, which paths were tried and rejected, what "done" means, what the next concrete check is. Start a fresh session and that context is gone — you re-explain, or the model guesses.

Catalyst closes that gap. When you approach a context limit, end a session, or brief a subagent, the **`handoff`** skill writes a **strongly-typed JSON brief** — a small, schema-validated state packet — and prepends the *why* to a durable project narrative. The next session reads the brief back and resumes from exactly where you left off, no re-explanation. The same brief shape powers subagent task descriptions and pipeline-stage contracts, so one schema serves every boundary.

Around that core, the other skills make the harness *ambient*: lifecycle hooks fire the right `handoff` mode automatically, an evidence gate blocks premature "it works" claims, evaluator rubrics enforce generator≠evaluator separation, and end-of-session detectors surface failure patterns before they compound. The skills trigger themselves — you don't manage them.

## What a handoff looks like

<p align="center">
  <img src="assets/demo/handoff.gif" alt="A typed handoff brief surviving a /compact: render the brief in a fresh session and resume exactly where you left off" width="860"/>
</p>

WRITE produces a typed, schema-validated brief; READ renders it back into a resume prompt the next session acts on directly — with guards that refuse a brief from a different branch or repo. Briefs are stored once per feature key in the **main worktree** (`<main>/.claude/handoffs/<key>.json`), so every linked worktree shares one store.

→ Full brief + render anatomy in **[docs/HARNESS.md](./docs/HARNESS.md#anatomy-of-a-handoff)**.

## Skills

| Skill | Purpose |
|-------|---------|
| [`handoff`](./skills/handoff/SKILL.md) | Structured context transfer for sessions, subagents, and pipelines. Six modes (WRITE / READ / RECOVER / REGROUND / SPLIT / BRIEF) plus PIPELINE orchestration. Typed JSON brief validated against a JSON Schema, feature-keyed, centralized worktree-aware store, render-on-read resume. REGROUND counters lost-in-the-middle; SPLIT forks a braided session into N self-contained briefs. |
| [`verify-gate`](./skills/verify-gate/SKILL.md) | PreToolUse hook that blocks "claim success" writes (test-results, build-status) unless the evidence file was Read first. Solves optimistic completion bias. Plus an opt-in over-reliance rule for large unverified agent diffs. |
| [`hook-builder`](./skills/hook-builder/SKILL.md) | Pre-built lifecycle hooks (PreCompact / SessionStart / Stop / UserPromptSubmit) that wire `handoff` into the session lifecycle. Turns Catalyst from explicit to ambient. |
| [`evaluator-library`](./skills/evaluator-library/SKILL.md) | 6 bundled domain rubrics (code-quality, ui-design, prose, security, performance, accessibility) dispatched with anti-self-grade enforced. |
| [`pipeline-templates`](./skills/pipeline-templates/SKILL.md) | 3 bundled executable pipeline templates (audit-then-fix, research-plan-implement-review, parallel-review-synthesize) + `/pipeline run / list / save`. |
| [`brain-bridge`](./skills/brain-bridge/SKILL.md) | MCP adapter that pulls Company Brain context into handoff PIPELINE briefs as pointers — never inlined. Configurable token budget + relevance threshold. |
| [`session-health`](./skills/session-health/SKILL.md) | Two-timing detector: per-turn degradation signals with recalibrated effective-window thresholds, and a session-end scan for 6 named failure patterns with recovery recipes. |

→ How each skill maps to Anthropic's harness primitives, plus the design principles → **[docs/HARNESS.md](./docs/HARNESS.md)**.

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

## Why "Catalyst"

The name says what it does: a catalyst facilitates a process without becoming part of the product. These skills facilitate the work between you and Claude — they activate when needed, smooth the handoff, then step out of the way without crowding the main context.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Skill proposals welcome via GitHub issues using the `new-skill` template. Proposals should ground themselves in a specific harness-engineering pattern from the [Anthropic article](https://www.anthropic.com/engineering/harness-design-long-running-apps) or call out the model-limitation assumption they encode.

## References

- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic's framework that grounds Catalyst's design
- [Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents.md) — the context-isolation primitives Catalyst builds on
- [docs/HARNESS.md](./docs/HARNESS.md) — the harness in depth: brief anatomy, primitive map, design principles

## License

MIT — see [LICENSE](./LICENSE).
