---
name: hooks
description: Use when installing Catalyst's pre-built lifecycle hooks (PreCompact → handoff WRITE, SessionStart → surface existing brief, Stop → flag uncommitted work, UserPromptSubmit → inject repo orientation), uninstalling them, scaffolding new hooks, or linting hook scripts. Turns Catalyst from explicit-only to ambient — handoff modes fire on lifecycle events instead of waiting for user invocation. Trigger phrases: "install hooks", "wire up handoff", "ambient mode", "/hooks", "hook scaffold", "hook lint".
---

# hooks

The skill that wires Catalyst into Claude Code's lifecycle. Without hooks, `handoff` is an explicit skill — useful but opt-in. With hooks's pre-built hooks installed, handoff modes fire automatically at the right lifecycle events.

## What the hooks do

| Hook | Event | What it triggers |
|------|-------|------------------|
| `PreCompact-handoff-write.sh` | About to `/compact` | Surfaces context asking Claude to invoke handoff WRITE before compaction destroys state |
| `SessionStart-handoff-read.sh` | New session opens | Detects `<branch>.json` in the centralized handoffs store (worktree-aware), prompts Claude to invoke handoff READ |
| `Stop-commit-backstop.sh` | Session ending | Flags any uncommitted git changes via additionalContext so next session can pick up |
| `UserPromptSubmit-orient.sh` | First user prompt of a session | Injects branch + last 5 commits as orientation context (only once per session) |

The `session-health` skill adds two more hooks (opt-in via `/session-health install`):

| Hook | Event | What it does |
|------|-------|--------------|
| `UserPromptSubmit-session-health.sh` | Every user prompt | Runs 4 per-turn degradation signals; emits one alert at the most urgent level |
| `Stop-session-health.sh` | Session ending | Scans transcript for 6 named failure patterns; logs each with a recovery recipe |
| `lib/session-health-signals.sh` | *(shared library)* | Sourced by both session-health hooks; contains all signal + pattern matchers |

All four are POSIX bash + jq. They fail-open on infrastructure errors (missing jq, no git repo, etc.) — Claude Code proceeds normally.

## Setup

```bash
/hooks install --all
```

Installs the four Tier-1 lifecycle hooks idempotently. Existing settings.json
hook entries are preserved (additive merge) — a re-install adds no duplicate
entry. The hook **script file itself is always re-copied** from the plugin into
`.claude/hooks/`, even when the settings entry already exists.

> **Re-run `install --all` after every plugin update.** Installed hooks live as
> *copies* in `.claude/hooks/`; upgrading the plugin cache does NOT refresh those
> copies. Until you re-install, a bug fixed in a new plugin version still runs the
> old, broken hook from `.claude/hooks/`. Re-running `install --all` overwrites the
> copies with the current version (the file copy is unconditional, so this is safe
> and cheap to run anytime).

The `session-health` hooks (UserPromptSubmit + Stop + lib/) are NOT included in `--all` — use `/session-health install` for those.

Or install one at a time:

```bash
/hooks install PreCompact
/hooks install SessionStart
```

## Uninstalling

```bash
/hooks uninstall --all
# or
/hooks uninstall PreCompact
```

Removes the hook script from `.claude/hooks/` and the entry from `.claude/settings.json`.

## Authoring new hooks

```bash
/hooks new PostToolUse my-custom-checker
```

Scaffolds `hooks/PostToolUse-my-custom-checker.sh` with the canonical structure: stdin JSON, jq check, exit-code semantics documented, fail-open default, TODO marker for your logic.

## Linting hooks

```bash
/hooks lint hooks/PreToolUse-verify-gate.sh
```

Checks for common mistakes:

- Matcher too broad (`.*`, empty string)
- Missing `set -euo pipefail`
- Missing jq dependency check
- Missing fail-open behavior on infrastructure error
- Filename doesn't match event prefix convention
- Bash syntax errors (`bash -n`)
- Hardcoded paths instead of `$CLAUDE_PROJECT_DIR`

Reports warnings and errors. Exit code 0 = clean, non-zero = issues found.

## Commands

| Command | What it does |
|---------|-------------|
| `/hooks install <event>` | Install the pre-built hook for that event |
| `/hooks install --all` | Install all four lifecycle hooks |
| `/hooks uninstall <event>` | Remove the pre-built hook |
| `/hooks uninstall --all` | Remove all four |
| `/hooks new <event> <name>` | Scaffold a new hook from template |
| `/hooks lint <path>` | Validate a hook script |
| `/hooks status` | List currently installed Catalyst hooks |

## Composition with other Catalyst skills

- `verify-gate` is NOT installed by `--all` (it's a separate opt-in). Use `/verify-gate install` for that one.
- `handoff` modes are what the lifecycle hooks invoke. PreCompact tells Claude to call WRITE; SessionStart tells Claude to call READ. The hooks are messengers — they don't replicate handoff's logic.
- Multiple PreToolUse / PostToolUse hooks compose: Claude Code runs them in parallel and the most-restrictive wins (deny > defer > ask > allow). hooks's lifecycle hooks don't fire on PreToolUse, so no conflict with verify-gate.

## Hook contract reference

See [`hooks/README.md`](../../hooks/README.md) for the full contract: stdin shape, output shape, exit codes, matcher conventions.

## Anti-patterns

- **Editing `.claude/settings.json` by hand.** Use `/hooks` commands — the script handles JSON merge correctly.
- **Installing the same hook twice.** Idempotent by design; second install is a no-op.
- **Writing a hook that depends on Python/Node.** v0.4 hooks are POSIX bash + jq only. Keeps install surface small.
- **Skipping `set -euo pipefail` in a custom hook.** It catches typos that would otherwise silently misfire.
- **Returning JSON without a `hookEventName` field.** Claude Code uses this to route the output; missing it means the decision is ignored.

## Model evolution

The whole skill assumes hooks remain the right enforcement layer. If Claude Code makes lifecycle-aware skills first-class (no scripts needed), much of hooks becomes vestigial. Review annually.
