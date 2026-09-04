<p align="center">
  <img src="assets/logo.svg" width="104" height="104" alt="Catalyst logo"/>
</p>

<h1 align="center">Catalyst</h1>

<p align="center">
  <strong>Harness engineering for coding agents — typed context handoffs that survive compaction, plus the lifecycle hooks that fire them. Runs on Claude Code and Codex; Claude-format compatible on GitHub Copilot, unverified.</strong>
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

This plugin is a catalyst for **human–AI collaboration**. It sits between you and the agent and smooths how you work together, then steps out of the way. In practice, it:

- **carries context across sessions** — so nothing gets re-explained after a `/compact`
- **keeps subagents on-scope** — the right minimum context, no bleed

Under the hood, Catalyst is grounded in **[harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps)** — the architectural patterns Anthropic itself uses to ship reliable agentic applications. It treats Claude not as a single chat but as a system that needs scaffolding for context resets, structured artifact handoffs, multi-agent orchestration, and explicit evaluator/generator separation.

## How it works

A long Claude session accumulates state that `/compact` quietly destroys: which decisions were made and why, which paths were tried and rejected, what "done" means, what the next concrete check is. Start a fresh session and that context is gone — you re-explain, or the model guesses.

Catalyst closes that gap. When you approach a context limit, end a session, or brief a subagent, the **`handoff`** skill writes a **strongly-typed JSON brief** — a small, schema-validated state packet — and prepends the *why* to a durable project narrative. The next session reads the brief back and resumes from exactly where you left off, no re-explanation. The same brief shape powers subagent task descriptions and evaluator briefs, so one schema serves every boundary.

Around that core, the `hooks` skill makes the harness *ambient*: lifecycle hooks fire the right `handoff` mode automatically. Both hooks are active from the moment the plugin installs — you don't run anything to turn them on.

## What a handoff looks like

<p align="center">
  <img src="assets/demo/handoff.gif" alt="A typed handoff brief surviving a /compact: render the brief in a fresh session and resume exactly where you left off" width="860"/>
</p>

WRITE produces a typed, schema-validated brief; READ renders it back into a resume prompt the next session acts on directly — with guards that refuse a brief from a different branch or repo. Briefs are stored once per feature key in the **main worktree** (`<main>/.claude/handoffs/<key>.json`), so every linked worktree shares one store.

→ Full brief + render anatomy in **[docs/HARNESS.md](./docs/HARNESS.md#anatomy-of-a-handoff)**.

## Skills

| Skill | Purpose | When to use |
|-------|---------|-------------|
| [`handoff`](./skills/handoff/SKILL.md) | Structured context transfer for sessions and subagents. Five modes (WRITE / READ / RECOVER / REGROUND / BRIEF). Typed JSON brief validated against a JSON Schema, feature-keyed, centralized worktree-aware store, render-on-read resume with REPO / BRANCH / STALE / MISSING drift guards. BRIEF carries the anti-self-grade + pre-coding-contract rules for evaluator subagents. | Ending a session, hitting a context limit, before `/clear` or `/compact`, resuming a prior session, or briefing a subagent. |
| [`hooks`](./skills/hooks/SKILL.md) | Both of Catalyst's hooks (PreCompact → handoff WRITE, SessionStart → auto-render the brief on clear/compact) are declared in `hooks/hooks.json` and active as soon as the plugin is installed — no install step. This skill authors new hooks and manages the two advisory ones. | Switching off the compaction suggestion or the resume announce, writing a new hook, checking hook status. |

→ How each skill maps to Anthropic's harness primitives, plus the design principles → **[docs/HARNESS.md](./docs/HARNESS.md)**.

## Install

Catalyst ships in Claude Code's plugin layout. Codex and GitHub Copilot read that layout too; every other agent gets the skills through the `skills` CLI. Hooks (auto-write on compaction, auto-render on session start) run only where the host loads them, listed per agent below. Nothing is enforced anywhere; both hooks only inject context.

### Claude Code

Skills, hooks and slash commands. Inside Claude Code:

```
/plugin marketplace add adrijshikhar/catalyst
/plugin install catalyst@catalyst
```

### Codex

Skills and hooks; no slash commands (invoke the skills by trigger phrase, or `$catalyst:handoff` style skill mentions).

```bash
codex plugin marketplace add adrijshikhar/catalyst
codex plugin add catalyst@catalyst
```

Then, once per install, inside Codex run `/hooks` and trust the two `catalyst@catalyst` entries. Until you do, Codex lists the hooks but does not run them.

### GitHub Copilot (VS Code, Copilot CLI)

Reads the Claude plugin layout per VS Code's docs. Unverified by the maintainer.

```bash
copilot plugin marketplace add adrijshikhar/catalyst
copilot plugin install catalyst@catalyst
```

### Antigravity CLI

Skills and slash-commands-as-skills through Antigravity's own plugin format (a root `plugin.json`). Antigravity's hook events (`PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, `Stop`) have no session-start or compaction event, so Catalyst's two hooks cannot run there; invoke `handoff` by trigger phrase.

```bash
agy plugin install https://github.com/adrijshikhar/catalyst
```

`agy` clones the repo itself. A local path works too (`agy plugin install ./catalyst`); the `owner/repo` shorthand does not.

### Gemini CLI, Cursor, Kiro and other agents

Skills only, no hooks yet. The [`skills`](https://github.com/vercel-labs/skills) CLI installs `handoff` and `hooks` into the agent's skills directory:

```bash
npx skills add adrijshikhar/catalyst --agent gemini-cli
```

Replace `gemini-cli` with `cursor`, `kiro-cli`, `antigravity` (the IDE), or `'*'` for every agent the CLI detects. The handoff scripts need Python 3. Windsurf has no skills or plugin system and is not supported.

### Rollback

Every release is a git tag (`vX.Y.Z`). On Claude Code:

```
/plugin install catalyst@catalyst@<version>
```

Releases: [github.com/adrijshikhar/catalyst/releases](https://github.com/adrijshikhar/catalyst/releases).

## Usage

After install, invoke skills explicitly or let Claude auto-trigger them:

- **Explicit:** `/handoff` to write a feature-keyed brief, `/handoff resume` to load one, `/handoff reground` to re-inject the goal mid-session, `/handoff list` to see every brief in the store, `/handoff prune` to propose orphans for deletion
- **Diagnostics:** `/hooks status` reports which hooks are registered and whether the two advisory ones are enabled
- **Auto:** when you end a session, switch context, approach context limits, or brief a subagent, Claude triggers the right mode of `handoff`

Both hooks are active as soon as the plugin is installed on Claude Code; on Codex after the one-time `/hooks` trust step. Don't want the compaction suggestion or the resume announce? `/hooks disable precompact` or `/hooks disable sessionstart`. See each skill's `SKILL.md` for full trigger conditions and behavior.

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
