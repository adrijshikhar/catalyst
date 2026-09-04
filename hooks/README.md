# Catalyst plugin-bundled hooks

This directory ships hook source for the lifecycle events of every host Catalyst runs on — Claude Code and Codex — plus GitHub Copilot, which reads the same Claude-format layout. Each hook is a single POSIX bash script that:

1. Reads JSON from stdin
2. Inspects the input (tool name, tool_input, session transcript path, etc.)
3. Writes JSON to stdout OR exits with a non-zero code to signal a decision
4. Exits 0 on success, 1 on hook-internal error (fail-open on every host)

## Hook contract reference

| Event | Input fields | Output fields | Common matchers |
|-------|-------------|---------------|-----------------|
| `PreToolUse` | `tool_name`, `tool_input`, `session_id`, `transcript_path` | `hookSpecificOutput.permissionDecision` ("allow" / "deny" / "ask" / "defer"), `hookSpecificOutput.permissionDecisionReason` | `Write\|Edit`, `Bash`, `^(Read)$` |
| `PostToolUse` | `tool_name`, `tool_input`, `tool_response`, `session_id`, `transcript_path` | `hookSpecificOutput.additionalContext`, `hookSpecificOutput.updatedToolOutput` | Same as PreToolUse |
| `PreCompact` | `session_id`, `transcript_path` | none required; side-effect (e.g., write file) is the point | (no matcher) |
| `SessionStart` | `session_id`, `cwd` | `hookSpecificOutput.additionalContext` (injected into context) | (no matcher) |
| `Stop` | `session_id`, `transcript_path` | none required; side-effect (e.g., commit) is the point | (no matcher) |
| `UserPromptSubmit` | `session_id`, `prompt`, `cwd` | `hookSpecificOutput.additionalContext` | (no matcher) |

## Fail-open default

Hooks never block. If a hook cannot run (jq missing, shared libraries absent) it exits 1, and exit 1 on infrastructure failure is documented as non-blocking on Claude Code and Codex for both of these events — the session continues either way. Copilot is unverified.

## Conventions

- File naming: `<Event>-<purpose>.sh` (e.g., `SessionStart-handoff-read.sh`)
- All hooks are POSIX bash. No Python or Node dependency.
- Hooks use `jq` for JSON parsing — required dependency. Each hook checks for `jq` itself and fails open if it is missing (no installer to check for it centrally).
- Hooks reference `$CLAUDE_PROJECT_DIR` for repo-relative paths.
- Hooks NEVER touch files outside the project dir (no `~/.claude/`, no `/tmp/` unless explicitly cache).

## Delivery — one declaration file

Catalyst ships one hook declaration file, `hooks/hooks.json`, in Claude Code's plugin layout. Codex reads `.claude-plugin/plugin.json` as a legacy manifest and loads the same file; VS Code and Copilot CLI read the Claude format too. Codex excludes hooks from Agent Plugins-format packages (`openai/codex` PR #37027), which is why Catalyst carries no root `plugin.json`.

| Hosts | File | Notes |
|---|---|---|
| Claude Code, Codex | `hooks/hooks.json` | Both read this path by default with the same schema. Codex runs a plugin hook only after the user trusts it once via `/hooks` in the Codex TUI (state persists under `[hooks.state]` in `~/.codex/config.toml`); untrusted hooks are listed but inert, including under `codex exec`. |
| VS Code (Copilot), Copilot CLI | `hooks/hooks.json` (Claude format) | Claude-format compatible per VS Code docs; unverified. |

Commands are written as `"${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/<script>.sh"`. Codex sets both variables and textually expands both exact tokens; VS Code expands `${PLUGIN_ROOT}`; Claude Code expands `${CLAUDE_PLUGIN_ROOT}`. Exact-token replacement never matches `${PLUGIN_ROOT:-`, so the expression survives and bash resolves whichever variable the host set. Scripts run from the plugin cache: the running script is always the one that shipped with the installed version.

`SessionStart`'s matcher is `""` (match-all) and must stay that way. Matcher
values for that event are exact-match over
`startup | resume | clear | compact | fork`; a matcher that lists sources —
e.g. `"startup|clear|compact"` — silently drops every source it omits. The
script branches on `.source` itself; `scripts/lint.py` rejects any
`SessionStart` matcher in `hooks.json` that is not a match-all form.

## Shared libraries (`hooks/lib/`)

Hook scripts run from the plugin tree, so `$SCRIPT_DIR/lib/` resolves inside
the plugin itself — no copying, nothing to reap.

| Library | Provides | Sourced by |
|---------|----------|-----------|
| `lib/config.sh` | `catalyst_project_root`, `catalyst_store_dir`, `catalyst_config_get`, `catalyst_config_json`, `catalyst_config_enabled` | PreCompact and SessionStart |

Source it defensively and surface degradation rather than dying silently:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/config.sh" 2>/dev/null || true
command -v catalyst_store_dir >/dev/null 2>&1 || { ...report degraded, exit 0... }
```

`scripts/lint.py` rejects a hook that inlines `rev-parse --git-common-dir` instead
of calling `catalyst_store_dir`.

## Testing a hook locally

```bash
echo '{"source":"startup","session_id":"x"}' | CLAUDE_PROJECT_DIR=$PWD bash hooks/SessionStart-handoff-read.sh
```

A hook with nothing to say exits 0 with no output. A hook that speaks emits valid JSON in the shape its event requires (see the contract table above).

## See also

- [Claude Code hooks docs](https://code.claude.com/docs/en/agent-sdk/hooks.md)
- [Anthropic CWC pattern (reference impl)](https://github.com/anthropics/cwc-long-running-agents)
- [Codex hooks docs](https://developers.openai.com/codex/hooks)
- [Agent Plugins specification](https://agent-plugins.org/specification) — the portable manifest Catalyst does not ship yet; Codex excludes hooks from that format (`openai/codex` #37027)
