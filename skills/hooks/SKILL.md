---
name: hooks
description: Use for Catalyst's two plugin-native lifecycle hooks (PreCompact → handoff WRITE, SessionStart → auto-render brief on clear/compact (one-line announce on startup/resume)) — checking hook status, disabling or re-enabling a Catalyst hook, scaffolding new hooks, or linting hook scripts. Trigger phrases: "hook status", "disable a Catalyst hook", "wire up handoff", "ambient mode", "/hooks", "hook scaffold", "hook lint", "author a hook".
---

# hooks

Wires Catalyst into the lifecycle of Claude Code, Codex and GitHub Copilot via one `hooks/hooks.json`. Both hooks run from the plugin cache — nothing to install.

## What the hooks do

| Hook | Event | What it triggers |
|------|-------|------------------|
| `PreCompact-handoff-write.sh` | About to `/compact` | Asks Claude to invoke handoff WRITE before compaction destroys state |
| `SessionStart-handoff-read.sh` | New session opens | Detects `<branch>.json` in the centralized store. Auto-renders on `clear`/`compact`; prompts handoff READ on `startup`/`resume` |

Both hooks are POSIX bash + jq, and fail-open on infrastructure errors (missing jq, no git repo).

## Setup

None — hooks are active as soon as the plugin is installed.

## Disabling a hook

```bash
/hooks disable precompact
/hooks disable sessionstart
```

Writes `hooks.precompact_prompt` / `hooks.sessionstart_resume` to `false` in `.claude/catalyst.json` — the only state. `/hooks enable <hook>` reverses it. **Falsy, case-insensitive: `false`, `0`, `no`, `off`.** Anything else — including the word `"disabled"` — is truthy; the hook stays enabled.

## Authoring and linting

```bash
/hooks new PostToolUse my-custom-checker
/hooks lint hooks/SessionStart-handoff-read.sh
```

`new` scaffolds `hooks/<event>-<name>.sh`: stdin JSON, jq check, exit-code semantics, fail-open default, TODO marker. `lint` checks matcher breadth (`.*`/empty), `set -euo pipefail`, jq check, fail-open behavior, event-prefix naming, `bash -n` syntax, and hardcoded paths instead of `$CLAUDE_PROJECT_DIR`. Exit code 0 = clean.

## Commands

| Command | What it does |
|---------|-------------|
| `/hooks status` | Report the two hooks and their state (deterministic, zero tokens) |
| `/hooks enable <precompact\|sessionstart>` | Turn an advisory hook back on |
| `/hooks disable <precompact\|sessionstart>` | Turn an advisory hook off |
| `/hooks new <event> <name>` | Scaffold a new hook from template |
| `/hooks lint <path>` | Validate a hook script |

## Composition with other Catalyst skills

- Both hooks are registered by `hooks/hooks.json` — nothing is installed or uninstalled.
- `handoff` modes are what the lifecycle hooks invoke — the hooks are messengers, not a reimplementation.
- Multiple PreToolUse / PostToolUse hooks compose: most-restrictive wins (deny > defer > ask > allow).

## Hook contract reference

See [`hooks/README.md`](../../hooks/README.md) for stdin/output shape, exit codes, matcher conventions.

## Anti-patterns

- **Editing `.claude/settings.json` or `.claude/catalyst.json` by hand for hook state.** Use `/hooks` commands.
- **Writing a hook that depends on Python/Node, or skipping `set -euo pipefail`.** POSIX bash + jq only; the strict mode catches typos that would otherwise silently misfire.
- **Returning JSON without `hookEventName`.** Claude Code, Codex and Copilot use it to route output; missing it means the decision is ignored.

## Model evolution

If Claude Code makes lifecycle-aware skills first-class, much of hooks becomes vestigial. If it adds native per-hook enable/disable, the two knobs and the `enable`/`disable` sub-commands retire and this skill shrinks to authoring alone. Review annually.

**Retired 2026-09-02 (v0.7.0):** `UserPromptSubmit-orient.sh` and `Stop-commit-backstop.sh`. Archived in the private planning repo.
