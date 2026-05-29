#!/usr/bin/env bash
# Stop-commit-backstop.sh — Catalyst hook-builder
#
# Fires when the session ends. If there are uncommitted changes in the working
# tree, surface them via additionalContext so the next session can pick up
# cleanly. Does NOT auto-commit (user might want to review).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | head -20)

if [ -z "$UNCOMMITTED" ]; then
  exit 0
fi

CTX="Session ending with uncommitted changes:

$UNCOMMITTED

Consider invoking the handoff skill in WRITE mode to preserve session state, then commit the changes manually or in the next session."

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $ctx
  }
}'
