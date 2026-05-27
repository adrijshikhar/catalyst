#!/usr/bin/env bash
# SessionStart-handoff-read.sh — Catalyst hook-builder
#
# Fires on session start. Detects whether a relevant handoff brief exists
# for the current branch. If so, injects a prompt to invoke handoff READ.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

BRANCH=""
if [ -d "$PROJECT_DIR/.git" ]; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

LEGACY_PATH="$PROJECT_DIR/.claude/HANDOFF.md"
KEYED_PATH=""
if [ -n "$BRANCH" ]; then
  KEY=$(echo "$BRANCH" | sed 's|/|-|g' | cut -c1-80)
  KEYED_PATH="$PROJECT_DIR/.claude/handoffs/$KEY.md"
fi

EXISTS_KEYED="no"
EXISTS_LEGACY="no"
[ -f "$KEYED_PATH" ] && [ -n "$KEYED_PATH" ] && EXISTS_KEYED="yes"
[ -f "$LEGACY_PATH" ] && EXISTS_LEGACY="yes"

if [ "$EXISTS_KEYED" = "no" ] && [ "$EXISTS_LEGACY" = "no" ]; then
  exit 0  # No brief, no message
fi

if [ "$EXISTS_KEYED" = "yes" ]; then
  CTX="A handoff brief exists for the current branch at $KEYED_PATH. Invoke the handoff skill in READ mode if the user wants to resume."
elif [ "$EXISTS_LEGACY" = "yes" ]; then
  CTX="A legacy handoff brief exists at $LEGACY_PATH. Invoke the handoff skill in READ mode (legacy / tier-3 fallback) if the user wants to resume."
fi

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
