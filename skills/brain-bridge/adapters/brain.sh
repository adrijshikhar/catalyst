#!/usr/bin/env bash
# skills/brain-bridge/adapters/brain.sh — brAIn adapter
#
# Reads brAIn raw output on stdin. Same env contract as gbrain.sh.
# Normalizes sections[] → results[] with type=decision (if document_id starts ADR-) or type=convention (if tag present).

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

BUDGET_POINTERS=$(( BUDGET / 20 ))
if [ "$BUDGET_POINTERS" -lt "$MAX_POINTERS" ]; then
  MAX_POINTERS="$BUDGET_POINTERS"
fi

# Fail-open on malformed input: emit empty results so caller can render brief without `## Brain pointers`.
NORMALIZED=$(echo "$RAW" | jq --argjson threshold "$THRESHOLD" --argjson max "$MAX_POINTERS" '
  (.sections // []) |
  map(select(.relevance >= $threshold)) |
  sort_by(-.relevance) |
  .[:$max] |
  map(
    if (.document_id | startswith("ADR-")) then
      {type: "decision", id: .document_id, date: .date, title: .title, relevance: .relevance}
    elif (.tag != null) then
      {type: "convention", tag: .tag, doc: .path, relevance: .relevance}
    else
      {type: "decision", id: .document_id, title: .title, relevance: .relevance}
    end
  )
' 2>/dev/null || echo "[]")

USED=$(echo "$NORMALIZED" | jq 'length * 20' 2>/dev/null || echo "0")
REMAINING=$(( BUDGET - USED ))
if [ "$REMAINING" -lt 0 ]; then REMAINING=0; fi

jq -n --arg q "$QUERY" --argjson results "$NORMALIZED" --argjson remaining "$REMAINING" \
  '{query: $q, results: $results, token_budget_remaining: $remaining}'
