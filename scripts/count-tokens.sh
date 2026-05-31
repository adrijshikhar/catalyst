#!/usr/bin/env bash
# scripts/count-tokens.sh — approximate token counter
# Usage: count-tokens.sh [file] or echo "text" | count-tokens.sh
# Supports char-count heuristic (4 chars ≈ 1 token) and optional tiktoken mode.
# Set CATALYST_TIKTOKEN=1 to use tiktoken if available; falls back to char heuristic.

set -euo pipefail

INPUT_TEXT=""

# Read from file argument or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT_TEXT="$(cat "$1")"
else
  INPUT_TEXT="$(cat)"
fi

# Real-usage fast path: if arg is a file with assistant `usage` objects (a
# session transcript), sum the actual token counts. Exact + free. Falls through
# to the heuristics below when no usage data is present.
if [ $# -ge 1 ] && [ -f "$1" ] && command -v jq >/dev/null 2>&1; then
  USAGE_SUM=$(jq -s '
    [ .[]
      | (.message.usage // .usage)
      | select(. != null)
      | ((.input_tokens // 0) + (.output_tokens // 0)
         + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
    ] | add // 0
  ' "$1" 2>/dev/null || echo 0)
  if [ -n "$USAGE_SUM" ] && [ "$USAGE_SUM" -gt 0 ] 2>/dev/null; then
    echo "$USAGE_SUM"
    exit 0
  fi
fi

# Tiktoken mode if CATALYST_TIKTOKEN=1
if [ "${CATALYST_TIKTOKEN:-0}" = "1" ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c "import tiktoken" 2>/dev/null; then
    echo "$INPUT_TEXT" | python3 -c "import sys, tiktoken; enc = tiktoken.get_encoding('cl100k_base'); text = sys.stdin.read(); print(len(enc.encode(text)))"
    exit 0
  else
    echo "WARN: CATALYST_TIKTOKEN=1 but tiktoken unavailable. Falling back to char heuristic." >&2
  fi
fi

# Char-count heuristic: 4 chars ≈ 1 token, round up
CHARS=$(printf "%s" "$INPUT_TEXT" | wc -c | tr -d ' ')
echo $(( (CHARS + 3) / 4 ))
