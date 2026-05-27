# Catalyst plugin-bundled hooks

This directory ships hook source for Claude Code lifecycle events. Each hook is a single POSIX bash script that:

1. Reads JSON from stdin
2. Inspects the input (tool name, tool_input, session transcript path, etc.)
3. Writes JSON to stdout OR exits with a non-zero code to signal a decision
4. Exits with code 0 on success, non-zero on hook-internal error (treated as fail-open by Claude Code)

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

If a hook errors (jq missing, malformed JSON, etc.), it exits with code 1 — Claude Code treats that as "ignore hook, proceed normally". Hooks NEVER block on infrastructure failure; they only block on policy violation (exit code 2 or JSON `permissionDecision: "deny"`).

## Conventions

- File naming: `<Event>-<purpose>.sh` (e.g., `PreToolUse-verify-gate.sh`)
- All hooks are POSIX bash. No Python dependency for v0.4.
- Hooks use `jq` for JSON parsing — required dependency. Installer checks for `jq`.
- Hooks reference `$CLAUDE_PROJECT_DIR` for repo-relative paths.
- Hooks NEVER touch files outside the project dir (no `~/.claude/`, no `/tmp/` unless explicitly cache).

## Testing a hook locally

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"test-results.json","content":"{}"}}' \
  | bash hooks/PreToolUse-verify-gate.sh
echo "Exit code: $?"
```

A failing matcher should exit 0. A matcher hit + policy violation should exit 2 OR emit JSON with `permissionDecision: "deny"`.

## See also

- [Catalyst Tier 1 spec](../docs/superpowers/specs/2026-05-24-tier-1-harness-primitives-design.md)
- [Claude Code hooks docs](https://code.claude.com/docs/en/agent-sdk/hooks.md)
- [Anthropic CWC pattern (reference impl)](https://github.com/anthropics/cwc-long-running-agents)
