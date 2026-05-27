#!/usr/bin/env bash
# PreCompact-handoff-write.sh — Catalyst hook-builder
#
# Fires before Claude Code compacts the session. Triggers a handoff WRITE so
# the brief survives the compaction. The agent reads back the brief on next
# session via SessionStart-handoff-read.sh.
#
# Implementation: emit additionalContext that tells Claude to invoke handoff WRITE.
# Claude Code injects this into the agent's context before compaction runs.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Resolve key (mirror handoff's tier ladder: explicit > branch > legacy)
BRANCH=""
if [ -d "$PROJECT_DIR/.git" ]; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

if [ -n "$BRANCH" ]; then
  KEY=$(echo "$BRANCH" | sed 's|/|-|g' | cut -c1-80)
  PATH_HINT=".claude/handoffs/$KEY.md"
else
  PATH_HINT=".claude/HANDOFF.md"
fi

REASON="About to compact. Invoke the handoff skill in WRITE mode to save current state to $PATH_HINT before context is summarized. Use the resolved key '$KEY' (or legacy slot if no branch)."

jq -n --arg ctx "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $ctx
  }
}'
