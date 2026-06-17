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

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Resolve the centralized handoffs store — anchored at the MAIN worktree
# (parent of the shared .git). Inlined (not calling scripts/handoff-dir.sh)
# because installed hooks ship standalone in .claude/hooks/ without scripts/.
# Mirrors scripts/handoff-dir.sh + handoff_paths.py (parity test guards those).
resolve_store() {
  local dir="$1" common
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)
  if [ -n "$common" ]; then
    case "$common" in /*) : ;; *) common="$dir/$common" ;; esac
    common=$(cd "$common" 2>/dev/null && pwd || echo "$common")
    if [ "$(basename "$common")" = ".git" ]; then
      echo "$(dirname "$common")/.claude/handoffs"
      return
    fi
  fi
  echo "$dir/.claude/handoffs"
}

# Resolve key (mirror handoff's tier ladder: explicit > branch > legacy)
BRANCH=""
KEY=""
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

if [ -n "$BRANCH" ]; then
  KEY=$(echo "$BRANCH" | sed 's|/|-|g' | cut -c1-80)
fi

STORE=$(resolve_store "$PROJECT_DIR")
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
