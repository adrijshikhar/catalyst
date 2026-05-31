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
#
# Opt-in rules (env-var gated, default OFF):
#   CATALYST_VERIFY_OVERRELIANCE=1
#     Emit "ask" when a large Write/Edit (>= CATALYST_OVERRELIANCE_MIN_BYTES,
#     default 4000) has no evidence file Read in the freshness window.
#     Decision is "ask" — not a hard deny — to avoid false-positive friction.
#     Grounded in: Anthropic PR-acceptance gap, METR agent slowdown research,
#     insecure-code-with-assistants studies (agent-generated code less durable).
#   CATALYST_OVERRELIANCE_MIN_BYTES (default 4000)
#     Minimum byte count of Write content or Edit new_string to trigger the rule.

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

FRESHNESS_MIN=$(echo "$CONFIG" | jq -r '.evidence_freshness_minutes // 10')

# ---------------------------------------------------------------------------
# Shared evidence-scan helper
# Sets EVIDENCE_FOUND and EVIDENCE_STALE for a given list of required files.
# Used by both the claim-rule check and the over-reliance check.
# Args: list of required file basenames (one per line) via stdin
# ---------------------------------------------------------------------------
scan_evidence_for_any_read() {
  local required_list="$1"
  EVIDENCE_FOUND=""
  EVIDENCE_STALE=""
  if [ ! -f "$TRANSCRIPT_PATH" ]; then
    return
  fi
  local NOW_EPOCH
  NOW_EPOCH=$(date -u +%s)
  local WINDOW_SEC=$(( FRESHNESS_MIN * 60 ))

  while IFS= read -r required; do
    local REQUIRED_BASE
    REQUIRED_BASE=$(basename "$required")
    # Find Read entries matching this required file
    local READ_LINE
    READ_LINE=$(jq -c --arg name "$REQUIRED_BASE" 'select(.type == "tool_use" and .name == "Read") | select((.input.file_path // "") | endswith($name))' < "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

    if [ -n "$READ_LINE" ]; then
      local READ_TS
      READ_TS=$(echo "$READ_LINE" | jq -r '.timestamp // ""')
      if [ -z "$READ_TS" ]; then
        EVIDENCE_FOUND="$required"
        return
      fi
      # Normalize fractional seconds (transcripts emit ...:00.123Z) which the
      # macOS strptime format below cannot parse — without this the parse fails
      # and the gate falls through to fail-OPEN. Strip the fraction, keep the Z.
      case "$READ_TS" in
        *.*) READ_TS="${READ_TS%.*}Z" ;;
      esac
      # Parse ISO 8601 timestamp (works on macOS + Linux)
      local READ_EPOCH
      if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s" >/dev/null 2>&1; then
        READ_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s")
      elif date -u -d "$READ_TS" "+%s" >/dev/null 2>&1; then
        READ_EPOCH=$(date -u -d "$READ_TS" "+%s")
      else
        EVIDENCE_FOUND="$required"
        return
      fi
      local AGE=$(( NOW_EPOCH - READ_EPOCH ))
      if [ "$AGE" -le "$WINDOW_SEC" ]; then
        EVIDENCE_FOUND="$required"
        return
      else
        EVIDENCE_STALE="$required (age ${AGE}s, window ${WINDOW_SEC}s)"
      fi
    fi
  done <<< "$required_list"
}

# ---------------------------------------------------------------------------
# Claim-rule check (original behavior)
# ---------------------------------------------------------------------------
CLAIM_BASENAME=$(basename "$FILE_PATH")
MATCHED_RULE=$(echo "$CONFIG" | jq -c --arg name "$CLAIM_BASENAME" '.claims[] | select(.writes_to == $name)' | head -1)

if [ -n "$MATCHED_RULE" ] && [ "$MATCHED_RULE" != "null" ]; then
  # A claim rule matched — enforce evidence gate
  REQUIRED_READS=$(echo "$MATCHED_RULE" | jq -r '.requires_read_of[]')
  scan_evidence_for_any_read "$REQUIRED_READS"

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
fi

# ---------------------------------------------------------------------------
# Over-reliance check (opt-in, default OFF)
# Gate: CATALYST_VERIFY_OVERRELIANCE=1
# Fires when no claim rule matched (general Write/Edit) but the content is
# large (>= CATALYST_OVERRELIANCE_MIN_BYTES) AND no file was Read in-window.
# Emits "ask" (not "deny") to surface a trust caution without hard-blocking.
# ---------------------------------------------------------------------------
OVERRELIANCE_ON="${CATALYST_VERIFY_OVERRELIANCE:-0}"
if [ "$OVERRELIANCE_ON" = "1" ]; then
  MIN_BYTES="${CATALYST_OVERRELIANCE_MIN_BYTES:-4000}"

  # Measure the write payload size
  # Write: tool_input.content; Edit: tool_input.new_string
  WRITE_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""')
  CONTENT_LEN=${#WRITE_CONTENT}

  if [ "$CONTENT_LEN" -ge "$MIN_BYTES" ]; then
    # Check whether ANY file was Read in the freshness window (not just claim files)
    ANY_RECENT_READ=""
    if [ -f "$TRANSCRIPT_PATH" ]; then
      NOW_EPOCH=$(date -u +%s)
      WINDOW_SEC=$(( FRESHNESS_MIN * 60 ))
      # Pick the most recent Read entry from the transcript
      LAST_READ_LINE=$(jq -c 'select(.type == "tool_use" and .name == "Read")' < "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
      if [ -n "$LAST_READ_LINE" ]; then
        READ_TS=$(echo "$LAST_READ_LINE" | jq -r '.timestamp // ""')
        if [ -z "$READ_TS" ]; then
          # No timestamp → treat as in-window (fail-open)
          ANY_RECENT_READ="yes"
        else
          case "$READ_TS" in *.*) READ_TS="${READ_TS%.*}Z" ;; esac
          if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s" >/dev/null 2>&1; then
            READ_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s")
          elif date -u -d "$READ_TS" "+%s" >/dev/null 2>&1; then
            READ_EPOCH=$(date -u -d "$READ_TS" "+%s")
          else
            # Parse failure → fail-open (treat as in-window)
            ANY_RECENT_READ="yes"
          fi
          if [ -z "$ANY_RECENT_READ" ]; then
            AGE=$(( NOW_EPOCH - READ_EPOCH ))
            if [ "$AGE" -le "$WINDOW_SEC" ]; then
              ANY_RECENT_READ="yes"
            fi
          fi
        fi
      fi
    fi

    if [ -z "$ANY_RECENT_READ" ]; then
      # Large output, no recent Read — surface trust caution
      OR_REASON="Over-reliance caution: about to write ${CONTENT_LEN} bytes of agent-generated output to ${FILE_PATH} with no evidence Read in the last ${FRESHNESS_MIN}-minute window. Unverified bulk output may contain errors or drift. Read a relevant file (the target, a test result, or a spec) before proceeding, or confirm you intend to proceed without review."
      jq -n --arg reason "$OR_REASON" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "ask",
          permissionDecisionReason: $reason
        }
      }'
      exit 0
    fi
  fi
fi

# No rule matched or rule satisfied — allow
exit 0
