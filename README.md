<p align="center">
  <img src="assets/logo.svg" width="104" height="104" alt="Catalyst logo"/>
</p>

<h1 align="center">Catalyst</h1>

<p align="center">
  <strong>Hand a coding session from one agent to another without losing the thread.</strong><br/>
  Start in Claude Code, continue in Codex or Antigravity — or just survive <code>/compact</code>. The context travels as a file in your repo, not as a memory in one vendor's chat.
</p>

<p align="center">
  <a href="https://github.com/adrijshikhar/catalyst/releases"><img src="https://img.shields.io/github/v/release/adrijshikhar/catalyst?style=flat&color=blue" alt="Release"></a>
  <a href="https://github.com/adrijshikhar/catalyst/actions/workflows/ci.yml"><img src="https://github.com/adrijshikhar/catalyst/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/adrijshikhar/catalyst?style=flat" alt="License"></a>
</p>

## The problem

Every long agent session ends the same way: `/compact`, a context limit, or you want a different model for the next step. The decisions, the rejected paths, what "done" means, the next check — gone, or re-explained from memory. And each vendor keeps that state in its own format, so switching agents means starting over.

## What Catalyst does

1. **Write.** The `handoff` skill (or the `PreCompact` hook, automatically) writes a typed, schema-validated brief to `.claude/handoffs/<branch>.json` in your repo's main worktree: goal, done-when, next acceptance check, decisions with rationale, rejected paths, open risks, files to read first.
2. **Switch.** Open the same repo in any agent that has Catalyst installed. The brief is plain JSON in your tree; it does not care who wrote it.
3. **Resume.** The `SessionStart` hook renders the brief back into the new session on Claude Code, Codex and Antigravity. Anywhere else, say `handoff resume`. Drift guards refuse a brief from another branch or repo and flag a stale one.

<p align="center">
  <img src="assets/demo/handoff.gif" alt="A brief written before /compact rendered back in a fresh session" width="860"/>
</p>

## Where it runs

| Host | Skills | `SessionStart` (resume) | `PreCompact` (auto-write) | Status |
|---|---|---|---|---|
| Claude Code | ✓ | ✓ | ✓ | verified |
| Codex CLI | ✓ | ✓ after one-time `/hooks` trust | ✓ after trust | hooks load verified |
| Antigravity CLI | ✓ (+ commands as skills) | ✓ | no compaction event | verified |
| GitHub Copilot (VS Code, CLI) | ✓ | Claude-format compatible | Claude-format compatible | unverified |
| Gemini CLI | ✓ + `AGENTS.md` as context | — | — | unverified |
| ~76 others via the `skills` CLI | ✓ | — | — | skills only |

Hooks never block anything and fail open; they only inject context. The brief is gitignored by default — commit it if the next agent runs on another machine.

## Install

**Claude Code**
```
/plugin marketplace add adrijshikhar/catalyst
/plugin install catalyst@catalyst
```

**Codex CLI** — then run `/hooks` once inside Codex and trust the two `catalyst@catalyst` entries.
```bash
codex plugin marketplace add adrijshikhar/catalyst && codex plugin add catalyst@catalyst
```

**Antigravity CLI**
```bash
agy plugin install https://github.com/adrijshikhar/catalyst
```

**GitHub Copilot CLI** (unverified)
```bash
copilot plugin marketplace add adrijshikhar/catalyst && copilot plugin install catalyst@catalyst
```

**Gemini CLI** (unverified)
```bash
gemini extensions install https://github.com/adrijshikhar/catalyst
```

**Anything else** — skills only, via [vercel-labs/skills](https://github.com/vercel-labs/skills):
```bash
npx skills add adrijshikhar/catalyst --agent cursor   # or kiro-cli, windsurf, opencode, '*' …
```

Requires Python 3 for the handoff scripts and `jq` for the hooks. Pin or roll back on Claude Code with `/plugin install catalyst@catalyst@<version>`.

## Skills

| Skill | What it does |
|-------|--------------|
| [`handoff`](./skills/handoff/SKILL.md) | WRITE / READ / RECOVER / REGROUND / BRIEF. Typed JSON brief, feature-keyed, centralized worktree-aware store, drift guards on read. |
| [`hooks`](./skills/hooks/SKILL.md) | Status and authoring for the two hooks that fire `handoff` automatically. |

## Use

- `/handoff` — write a brief for the current branch; `/handoff resume` — render it; `/handoff reground` — re-inject the goal mid-session; `/handoff list` / `prune` — manage the store. Slash commands are Claude Code only; elsewhere ask for the `handoff` skill by name.
- `/hooks status` — what is registered; `/hooks disable precompact|sessionstart` — quiet one hook.

Full brief anatomy, design principles and the host matrix in depth: **[docs/HARNESS.md](./docs/HARNESS.md)**. Grounded in Anthropic's [harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps) patterns.

## Contributing & license

[CONTRIBUTING.md](./CONTRIBUTING.md). MIT — see [LICENSE](./LICENSE).
