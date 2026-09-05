#!/usr/bin/env bash
# PreCompact-handoff-write.sh — Catalyst hooks
#
# Fires before Claude Code compacts the session. Triggers a handoff WRITE so
# the brief survives the compaction. The agent reads back the brief on next
# session via SessionStart-handoff-read.sh.
#
# Implementation: emit a top-level `systemMessage` telling Claude to invoke
# handoff WRITE. PreCompact does NOT accept `hookSpecificOutput` — emitting it
# fails schema validation ("Hook JSON output validation failed"). systemMessage
# is the only injection channel for this event.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Fail-open on missing jq. Must precede every jq use, including the degraded
# message below.
if ! command -v jq >/dev/null 2>&1; then exit 1; fi

# Project dir: Claude Code sets CLAUDE_PROJECT_DIR; Codex and Antigravity do not,
# but every host puts `cwd` in the hook payload. Fall back to it, then to pwd.
INPUT="$(cat 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)}"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"

# Shared libraries live in ONE place: hooks/lib/. Hooks run from the plugin
# tree (declared in hooks.json at the repo root), so this resolves inside the plugin
# itself. Fail open, but surface the degradation — a hook that silently loses
# its function is its own bug (P9).
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/config.sh" 2>/dev/null || true
if ! command -v catalyst_store_dir >/dev/null 2>&1; then
  jq -n '{systemMessage: "Catalyst PreCompact hook is degraded: hooks/lib/config.sh was not found beside this hook, which means the plugin cache is incomplete. Reinstall the plugin. Skipping the handoff-WRITE prompt for this compaction."}'
  exit 0
fi

# Opt out: `hooks.precompact_prompt: false` in .claude/catalyst.json, or
# CATALYST_HOOKS_PRECOMPACT_PROMPT=false. Silent by design — a disabled hook
# that still prints has not been disabled.
if ! catalyst_config_enabled hooks.precompact_prompt; then
  exit 0
fi

# Resolve key (mirror handoff's tier ladder: explicit > branch > legacy)
BRANCH=""
KEY=""
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

if [ -n "$BRANCH" ]; then
  KEY=$(echo "$BRANCH" | sed 's|/|-|g' | cut -c1-80)
fi

STORE=$(catalyst_store_dir "$PROJECT_DIR")
if [ -n "$KEY" ]; then
  PATH_HINT="$STORE/$KEY.json"
else
  PATH_HINT="$STORE/HANDOFF.json"
fi

if [ -n "$KEY" ]; then
  REASON="About to compact. Invoke the handoff skill in WRITE mode to save current state to $PATH_HINT before context is summarized. Use the resolved key '$KEY'."
else
  REASON="About to compact. Invoke the handoff skill in WRITE mode to save current state to $PATH_HINT (legacy slot — no branch) before context is summarized."
fi

jq -n --arg ctx "$REASON" '{systemMessage: $ctx}'
