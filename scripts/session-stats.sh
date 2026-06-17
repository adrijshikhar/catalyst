#!/usr/bin/env bash
# scripts/session-stats.sh — render a compact session stats report.
# Reads the session transcript (real token usage via count-tokens.sh), plus the
# tail of the .claude/session-health.log. Pure read; no model.
#
# Usage: session-stats.sh <transcript_path>
# Env: CLAUDE_PROJECT_DIR (for log locations).
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSCRIPT="${1:-}"

echo "=== Catalyst session stats ==="

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TOKENS=$(bash "$SCRIPT_DIR/count-tokens.sh" "$TRANSCRIPT" 2>/dev/null || echo "?")
  echo "Approx tokens this session: $TOKENS"
  if command -v jq >/dev/null 2>&1; then
    CACHE_READ=$(jq -s '[.[] | (.message.usage // .usage) | select(.!=null) | (.cache_read_input_tokens // 0)] | add // 0' "$TRANSCRIPT" 2>/dev/null || echo 0)
    echo "Cache-read tokens: $CACHE_READ"
  fi
else
  echo "Approx tokens this session: (no transcript)"
fi

# Honor a configured log_path, else the live default.
HEALTH_LOG="$PROJECT_DIR/.claude/session-health.log"
CFG="$PROJECT_DIR/.claude/session-health.json"
if [ -f "$CFG" ] && command -v jq >/dev/null 2>&1; then
  CFG_PATH=$(jq -r '.log_path // empty' "$CFG" 2>/dev/null || true)
  if [ -n "$CFG_PATH" ]; then
    case "$CFG_PATH" in
      *..*) ;;                                                  # traversal → keep default HEALTH_LOG
      "$PROJECT_DIR"/*) HEALTH_LOG="$CFG_PATH" ;;               # absolute, inside project
      /*) ;;                                                    # absolute outside project → keep default
      ?*) HEALTH_LOG="$PROJECT_DIR/$CFG_PATH" ;;                # relative
    esac
  fi
fi

if [ -f "$HEALTH_LOG" ]; then
  echo "--- recent session-health alerts ---"
  tail -n 5 "$HEALTH_LOG"
else
  echo "--- no session-health alerts ---"
fi
