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
