#!/usr/bin/env bash
# skills/brain-bridge/adapters/gbrain.sh — gbrain adapter
#
# Reads gbrain raw output on stdin, applies relevance threshold + token budget,
# prints normalized pointer JSON to stdout.
#
# Env config (read from .claude/brain-bridge.json by parent, passed via env):
#   BB_QUERY=<query phrase>                  (required)
#   BB_RELEVANCE_THRESHOLD=<0.0-1.0>          (default 0.5)
#   BB_TOKEN_BUDGET=<int>                     (default 2000)
#   BB_MAX_POINTERS=<int>                     (default 6)
#
# Output JSON shape:
#   {"query": "...", "results": [{"type":"file","path":"...","lines":"42-78","relevance":0.91}, ...], "token_budget_remaining": <int>}

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"query":"","results":[],"token_budget_remaining":0}'
  echo "ERROR: jq required" >&2
  exit 1
fi

QUERY="${BB_QUERY:-}"
THRESHOLD="${BB_RELEVANCE_THRESHOLD:-0.5}"
BUDGET="${BB_TOKEN_BUDGET:-2000}"
MAX_POINTERS="${BB_MAX_POINTERS:-6}"

RAW="$(cat)"

# Each pointer ~= 20 tokens (path + lines + relevance). Cap by both budget and max_pointers.
BUDGET_POINTERS=$(( BUDGET / 20 ))
if [ "$BUDGET_POINTERS" -lt "$MAX_POINTERS" ]; then
  MAX_POINTERS="$BUDGET_POINTERS"
fi

# Normalize gbrain shape: pages[].{path, line_start, line_end, score} → results[].{type:file, path, lines, relevance}
# Fail-open on malformed input: emit empty results array so caller can render brief without `## Brain pointers`.
NORMALIZED=$(echo "$RAW" | jq --argjson threshold "$THRESHOLD" --argjson max "$MAX_POINTERS" '
  (.pages // []) |
  map(select(.score >= $threshold)) |
  sort_by(-.score) |
  .[:$max] |
  map({
    type: "file",
    path: .path,
    lines: ("\(.line_start)-\(.line_end)"),
    relevance: .score
  })
' 2>/dev/null || echo "[]")

USED=$(echo "$NORMALIZED" | jq 'length * 20' 2>/dev/null || echo "0")
REMAINING=$(( BUDGET - USED ))
if [ "$REMAINING" -lt 0 ]; then REMAINING=0; fi

jq -n --arg q "$QUERY" --argjson results "$NORMALIZED" --argjson remaining "$REMAINING" \
  '{query: $q, results: $results, token_budget_remaining: $remaining}'
