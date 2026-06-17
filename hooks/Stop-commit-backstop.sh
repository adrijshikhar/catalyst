#!/usr/bin/env bash
# Stop-commit-backstop.sh — Catalyst hook-builder
#
# Fires when the session ends. If there are uncommitted changes in the working
# tree, surface them via a top-level `systemMessage` so the next session can
# pick up cleanly. Does NOT auto-commit (user might want to review).
#
# NOTE: Stop hooks do NOT accept `hookSpecificOutput.additionalContext` — that
# shape fails schema validation. Use `systemMessage` (same as Stop-session-health.sh).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INPUT="$(cat)"
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | head -20)

if [ -z "$UNCOMMITTED" ]; then
  exit 0
fi

# De-noise: emit only when the dirty-state fingerprint changed since last turn.
SID=$(printf '%s' "${SESSION_ID:-}" | tr -c 'a-zA-Z0-9_.-' '_')
MARKER="/tmp/catalyst-scb-${SID:-nosession}"
HASH=$(printf '%s' "$UNCOMMITTED" | cksum | awk '{print $1}')
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$HASH" ]; then
  exit 0
fi
printf '%s' "$HASH" > "$MARKER" 2>/dev/null || true

CTX="Uncommitted changes in the working tree:

$UNCOMMITTED

Consider invoking the handoff skill in WRITE mode to preserve session state, then commit."

jq -n --arg ctx "$CTX" '{systemMessage: $ctx}'
