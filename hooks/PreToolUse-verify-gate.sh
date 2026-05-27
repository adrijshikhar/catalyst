#!/usr/bin/env bash
# PreToolUse-verify-gate.sh — Catalyst verify-gate hook
#
# Blocks Write/Edit tool calls that claim success without prior evidence Read.
# Reads stdin JSON, returns stdout JSON with permissionDecision.
#
# Exit codes:
#   0 — allow (matches no rule, or rule satisfied)
#   2 — deny (rule matched, evidence missing/stale)
#   1 — infra error (fail-open: Claude Code ignores hook)
#
# Config:
#   $CLAUDE_PROJECT_DIR/.claude/verify-gate.json — project overrides
#   Falls back to built-in defaults if missing.

set -euo pipefail

# Fail-open on missing jq
if ! command -v jq >/dev/null 2>&1; then
  exit 1
fi

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/verify-gate.json"

# Built-in default rules
DEFAULT_CONFIG='{
  "claims": [
    {"writes_to": "test-results.json", "requires_read_of": ["test-output.log", "vitest-results.xml", "pytest.xml", "jest-results.json"]},
    {"writes_to": "build-status.txt", "requires_read_of": ["build.log", "tsc-output.log"]}
  ],
  "evidence_freshness_minutes": 10
}'

if [ -f "$CONFIG_FILE" ]; then
  CONFIG=$(cat "$CONFIG_FILE")
else
  CONFIG="$DEFAULT_CONFIG"
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Only inspect Write/Edit tools
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# No file_path? Allow.
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Find the matching claim rule
CLAIM_BASENAME=$(basename "$FILE_PATH")
MATCHED_RULE=$(echo "$CONFIG" | jq -c --arg name "$CLAIM_BASENAME" '.claims[] | select(.writes_to == $name)' | head -1)

# No matching rule → allow
if [ -z "$MATCHED_RULE" ] || [ "$MATCHED_RULE" = "null" ]; then
  exit 0
fi

REQUIRED_READS=$(echo "$MATCHED_RULE" | jq -r '.requires_read_of[]')
FRESHNESS_MIN=$(echo "$CONFIG" | jq -r '.evidence_freshness_minutes // 10')

# Inspect transcript for matching Read entries
EVIDENCE_FOUND=""
EVIDENCE_STALE=""
if [ -f "$TRANSCRIPT_PATH" ]; then
  NOW_EPOCH=$(date -u +%s)
  WINDOW_SEC=$((FRESHNESS_MIN * 60))

  while IFS= read -r required; do
    REQUIRED_BASE=$(basename "$required")
    # Find Read entries matching this required file
    READ_LINE=$(jq -c --arg name "$REQUIRED_BASE" 'select(.type == "tool_use" and .name == "Read") | select((.input.file_path // "") | endswith($name))' < "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

    if [ -n "$READ_LINE" ]; then
      READ_TS=$(echo "$READ_LINE" | jq -r '.timestamp // ""')
      if [ -z "$READ_TS" ]; then
        EVIDENCE_FOUND="$required"
        break
      fi
      # Parse ISO 8601 timestamp (works on macOS + Linux)
      if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s" >/dev/null 2>&1; then
        READ_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s")
      elif date -u -d "$READ_TS" "+%s" >/dev/null 2>&1; then
        READ_EPOCH=$(date -u -d "$READ_TS" "+%s")
      else
        EVIDENCE_FOUND="$required"
        break
      fi
      AGE=$((NOW_EPOCH - READ_EPOCH))
      if [ "$AGE" -le "$WINDOW_SEC" ]; then
        EVIDENCE_FOUND="$required"
        break
      else
        EVIDENCE_STALE="$required (age ${AGE}s, window ${WINDOW_SEC}s)"
      fi
    fi
  done <<< "$REQUIRED_READS"
fi

if [ -n "$EVIDENCE_FOUND" ]; then
  exit 0
fi

# Build denial reason
if [ -n "$EVIDENCE_STALE" ]; then
  REASON="Evidence is stale: $EVIDENCE_STALE. Re-read the evidence file within the $FRESHNESS_MIN-minute freshness window before claiming success."
else
  REQUIRED_LIST=$(echo "$REQUIRED_READS" | tr '\n' ', ' | sed 's/,$//')
  REASON="Cannot write to $FILE_PATH without first Reading evidence. Required: one of [$REQUIRED_LIST]. Read the relevant evidence file, then retry the write."
fi

# Emit JSON deny decision
jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 2
