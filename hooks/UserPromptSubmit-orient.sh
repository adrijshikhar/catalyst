#!/usr/bin/env bash
# UserPromptSubmit-orient.sh — Catalyst hooks
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

# Sanitize session_id before it touches the filesystem — it's external input
# and flows into a path. Strip anything outside [A-Za-z0-9_-] (no traversal).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Prune stale markers (>7 days) so .claude/ doesn't accumulate forever.
find "$PROJECT_DIR/.claude" -maxdepth 1 -name '.catalyst-oriented-*' -type f -mtime +7 -delete 2>/dev/null || true

# Per-session marker
MARKER_PATH="$MARKER-$SESSION_ID"
if [ -f "$MARKER_PATH" ]; then
  exit 0  # Already oriented this session
fi

if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
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
