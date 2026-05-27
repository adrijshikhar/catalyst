#!/usr/bin/env bash
# UserPromptSubmit-orient.sh — Catalyst hook-builder
#
# Fires on user prompt submission. Injects orientation context for FIRST prompt
# of a session: branch name + last 5 commits. Skips injection on subsequent
# prompts (Claude already knows the orientation).
#
# Uses a marker file at .claude/.catalyst-oriented to track per-session state.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MARKER="$PROJECT_DIR/.claude/.catalyst-oriented"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Per-session marker
MARKER_PATH="$MARKER-$SESSION_ID"
if [ -f "$MARKER_PATH" ]; then
  exit 0  # Already oriented this session
fi

if [ ! -d "$PROJECT_DIR/.git" ]; then
  exit 0
fi

BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "(detached)")
RECENT_COMMITS=$(git -C "$PROJECT_DIR" log --oneline -5 2>/dev/null || echo "")

CTX="Repo orientation:
Branch: $BRANCH

Recent commits:
$RECENT_COMMITS"

mkdir -p "$(dirname "$MARKER_PATH")"
touch "$MARKER_PATH"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
