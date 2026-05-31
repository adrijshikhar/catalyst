#!/usr/bin/env bash
# scripts/session-stats.sh — render a compact session stats report.
# Reads the session transcript (real token usage via count-tokens.sh), plus the
# tails of the degradation + failure-pattern logs. Pure read; no model.
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

DEG_LOG="$PROJECT_DIR/.claude/session-degradation.log"
if [ -f "$DEG_LOG" ]; then
  echo "--- recent degradation alerts ---"
  tail -n 5 "$DEG_LOG"
else
  echo "--- no degradation alerts ---"
fi

FAIL_LOG="$PROJECT_DIR/.claude/failure-patterns.log"
if [ -f "$FAIL_LOG" ]; then
  echo "--- recent failure patterns ---"
  tail -n 5 "$FAIL_LOG"
else
  echo "--- no failure patterns ---"
fi
