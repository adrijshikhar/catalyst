#!/usr/bin/env bash
# UserPromptSubmit-session-degradation-watch.sh — Catalyst session-degradation-watch
#
# Fires on every user prompt. Reads the transcript, checks 4 signals,
# emits additionalContext with the MOST URGENT alert (single-message bar).
#
# Composes with Tier 1's UserPromptSubmit-orient.sh — multiple UserPromptSubmit
# hooks fire on the same event; each adds context independently.
#
# Signals:
#   1. context_pct  (>= 60% warn, >= 75% strong, >= 85% force)
#   2. repeated tool call (same input ×3 in last 5 turns)
#   3. stale read (Edit on file F where last Read of F was >15 turns ago)
#   4. contradiction with .claude/PROJECT_STATE.md
#
# Exit codes:
#   0 — done. If any signal fired: stdout is one hook JSON line. If no signal
#       fired (clean session): stdout is empty (no false-positive alerts).
#   non-zero — fail-open (Claude Code ignores hook)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 1  # fail-open
fi

INPUT="$(cat)"
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  # No transcript yet (fresh session) — emit nothing
  exit 0
fi

# Load config
CONFIG_FILE="$PROJECT_DIR/.claude/session-degradation-watch.json"
WARN_PCT=60
STRONG_PCT=75
FORCE_PCT=85
REPEAT_COUNT=3
REPEAT_WINDOW=5
STALE_TURNS=15
CHECK_CONTRADICTION=1
LOG_PATH="$PROJECT_DIR/.claude/session-degradation.log"

if [ -f "$CONFIG_FILE" ]; then
  WARN_PCT=$(jq -r '.context_thresholds.warn // 60' "$CONFIG_FILE")
  STRONG_PCT=$(jq -r '.context_thresholds.strong // 75' "$CONFIG_FILE")
  FORCE_PCT=$(jq -r '.context_thresholds.force // 85' "$CONFIG_FILE")
  REPEAT_COUNT=$(jq -r '.repeated_tool_call_count // 3' "$CONFIG_FILE")
  REPEAT_WINDOW=$(jq -r '.repeated_tool_call_window_turns // 5' "$CONFIG_FILE")
  STALE_TURNS=$(jq -r '.stale_read_max_turns // 15' "$CONFIG_FILE")
  CHECK_CONTRADICTION=$(jq -r '.check_contradiction_with_project_state // true | if . then 1 else 0 end' "$CONFIG_FILE")
  LOG_PATH=$(jq -r ".log_path // \"$PROJECT_DIR/.claude/session-degradation.log\"" "$CONFIG_FILE")
fi

# === Signal 1: context % ===
# Prefer the shared count-tokens.sh helper (honors CATALYST_TIKTOKEN=1 for exact
# counts via tiktoken; falls back to chars/4 heuristic otherwise). If the helper
# isn't where we expect (e.g., minimal install), inline the same heuristic.
COUNT_TOKENS_BIN="$PROJECT_DIR/scripts/count-tokens.sh"
if [ -x "$COUNT_TOKENS_BIN" ]; then
  APPROX_TOKENS=$("$COUNT_TOKENS_BIN" "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
else
  TOTAL_CHARS=$(wc -c < "$TRANSCRIPT_PATH" | tr -d ' ')
  APPROX_TOKENS=$(( (TOTAL_CHARS + 3) / 4 ))
fi
CONTEXT_BUDGET=200000
CONTEXT_PCT=$(( (APPROX_TOKENS * 100) / CONTEXT_BUDGET ))

# === Signal 2: repeated tool call ===
REPEATED_KEY=""
REPEATED_COUNT=0
RECENT_TOOL_USES=$(jq -c 'select(.type=="tool_use") | {name, input: (.input | tostring)}' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n "$REPEAT_WINDOW" || echo "")
if [ -n "$RECENT_TOOL_USES" ]; then
  MOST_FREQUENT=$(echo "$RECENT_TOOL_USES" | sort | uniq -c | sort -rn | head -1 || echo "")
  if [ -n "$MOST_FREQUENT" ]; then
    REPEATED_COUNT=$(echo "$MOST_FREQUENT" | awk '{print $1}')
    REPEATED_KEY=$(echo "$MOST_FREQUENT" | sed 's/^ *[0-9]* *//' | jq -r '"\(.name):\(.input | fromjson | .command // .file_path // .pattern // "?")"' 2>/dev/null || echo "?")
  fi
fi

# === Signal 3: stale read ===
STALE_FILE=""
LAST_EDIT_LINE=$(jq -c 'select(.type=="tool_use" and .name=="Edit")' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
if [ -n "$LAST_EDIT_LINE" ]; then
  EDIT_FILE=$(echo "$LAST_EDIT_LINE" | jq -r '.input.file_path // empty')
  EDIT_TURN=$(echo "$LAST_EDIT_LINE" | jq -r '.turn // 0')
  if [ -n "$EDIT_FILE" ]; then
    LAST_READ_TURN=$(jq -r --arg f "$EDIT_FILE" 'select(.type=="tool_use" and .name=="Read" and .input.file_path==$f) | .turn' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || echo "0")
    if [ -n "$LAST_READ_TURN" ] && [ "$LAST_READ_TURN" -gt 0 ]; then
      GAP=$(( EDIT_TURN - LAST_READ_TURN ))
      if [ "$GAP" -gt "$STALE_TURNS" ]; then
        STALE_FILE="$EDIT_FILE"
      fi
    fi
  fi
fi

# === Signal 4: contradiction with PROJECT_STATE.md ===
CONTRADICTION_TEXT=""
PROJECT_STATE="$PROJECT_DIR/.claude/PROJECT_STATE.md"
if [ "$CHECK_CONTRADICTION" = "1" ] && [ -f "$PROJECT_STATE" ]; then
  LAST_ASSISTANT=$(jq -r 'select(.type=="assistant") | .content // empty' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
  while IFS= read -r decision; do
    NOT_PART=$(echo "$decision" | sed -n 's/.*\bnot\s\+\([a-zA-Z][a-zA-Z _]*\).*/\1/p' | head -1 | tr -d '\n')
    USE_PART=$(echo "$decision" | sed -n 's/.*\buse\s\+\([a-zA-Z][a-zA-Z _]*\)\s\+not.*/\1/p' | head -1 | tr -d '\n')
    if [ -n "$NOT_PART" ] && [ -n "$USE_PART" ]; then
      if echo "$LAST_ASSISTANT" | grep -qi "$NOT_PART" && ! echo "$LAST_ASSISTANT" | grep -qi "$USE_PART"; then
        CONTRADICTION_TEXT="contradicts PROJECT_STATE decision: '$decision' (chat mentions '$NOT_PART', should be '$USE_PART')"
        break
      fi
    fi
  done < <(grep -h "^Decision:" "$PROJECT_STATE" 2>/dev/null || echo "")
fi

# === Decide most urgent alert ===
ALERT=""
if [ "$CONTEXT_PCT" -ge "$FORCE_PCT" ]; then
  ALERT="CONTEXT FORCE: ${CONTEXT_PCT}% used (≥${FORCE_PCT}%). Call handoff WRITE NOW — context is critically full. Use /catalyst:handoff (no arg)."
elif [ "$CONTEXT_PCT" -ge "$STRONG_PCT" ]; then
  ALERT="CONTEXT STRONG: ${CONTEXT_PCT}% used (≥${STRONG_PCT}%). Strongly consider handoff WRITE before the next big task. Use /catalyst:handoff."
elif [ -n "$CONTRADICTION_TEXT" ]; then
  ALERT="CONTRADICTION: $CONTRADICTION_TEXT. Verify against .claude/PROJECT_STATE.md before proceeding."
elif [ -n "$STALE_FILE" ]; then
  ALERT="STALE READ: most recent Edit on '$STALE_FILE' followed a Read >${STALE_TURNS} turns ago. Re-Read '$STALE_FILE' before further edits to avoid old_string mismatch."
elif [ "$REPEATED_COUNT" -ge "$REPEAT_COUNT" ] && [ "$REPEATED_COUNT" -gt 0 ]; then
  ALERT="REPEATED TOOL CALL: '$REPEATED_KEY' ran $REPEATED_COUNT times in last $REPEAT_WINDOW turns. Try a different approach (different command, different file, or ask user)."
elif [ "$CONTEXT_PCT" -ge "$WARN_PCT" ]; then
  ALERT="CONTEXT WARN: ${CONTEXT_PCT}% used (≥${WARN_PCT}%). Consider running handoff WRITE soon to checkpoint progress."
fi

# === Emit hook output + log ===
if [ -n "$ALERT" ]; then
  mkdir -p "$(dirname "$LOG_PATH")"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$TS] $ALERT" >> "$LOG_PATH"
  jq -n --arg msg "$ALERT" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
fi

exit 0
