#!/usr/bin/env bash
# Stop-failure-pattern-detect.sh — Catalyst failure-pattern-detector
#
# Fires when the session ends. Scans the transcript for 6 known failure patterns.
# Writes hits to .claude/failure-patterns.log with timestamp + pattern + recovery
# recipe. Outputs a brief additionalContext summary if any patterns matched.
#
# Patterns detected (v0.5):
#   - instruction-fade        : same user instruction repeated 2+ times in last 10 turns
#   - context-drowning        : single tool output >10KB (heuristic; flagged not fixed)
#   - edit-mismatch           : 2+ "old_string not found" errors in last 5 turns
#   - stale-read              : Edit on file F where F was Written between last Read of F and this Edit
#   - repeated-tool-call      : same Bash/Read/Grep input 3+ times within 5 turns
#   - recovery-spiral         : 3+ consecutive turns starting with Read on previously-seen file
#
# Exit codes:
#   0 — done (with or without detections); any output is on stdout
#   1 — infra error (fail-open: Claude Code ignores hook)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 1
fi

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

CONFIG_FILE="$PROJECT_DIR/.claude/failure-pattern-detector.json"
LOG_PATH="$PROJECT_DIR/.claude/failure-patterns.log"

# Built-in defaults
ENABLED='["instruction-fade","edit-mismatch","stale-read","repeated-tool-call","recovery-spiral","context-drowning"]'
REPEATED_COUNT=3
REPEATED_WINDOW=5
STALE_MAX_TURNS=15
EDIT_MISMATCH_COUNT=2
SPIRAL_COUNT=3

if [ -f "$CONFIG_FILE" ]; then
  ENABLED=$(jq -c '.enabled_patterns // ["instruction-fade","edit-mismatch","stale-read","repeated-tool-call","recovery-spiral","context-drowning"]' "$CONFIG_FILE")
  REPEATED_COUNT=$(jq -r '.thresholds.repeated_tool_call_count // 3' "$CONFIG_FILE")
  REPEATED_WINDOW=$(jq -r '.thresholds.repeated_tool_call_window_turns // 5' "$CONFIG_FILE")
  STALE_MAX_TURNS=$(jq -r '.thresholds.stale_read_max_turns // 15' "$CONFIG_FILE")
  EDIT_MISMATCH_COUNT=$(jq -r '.thresholds.edit_mismatch_count // 2' "$CONFIG_FILE")
  SPIRAL_COUNT=$(jq -r '.thresholds.recovery_spiral_count // 3' "$CONFIG_FILE")
fi

is_enabled() {
  local pattern="$1"
  echo "$ENABLED" | jq -e --arg p "$pattern" 'any(. == $p)' >/dev/null 2>&1
}

mkdir -p "$(dirname "$LOG_PATH")"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DETECTIONS=""

emit() {
  local pattern="$1"
  local detail="$2"
  local recipe="$3"
  echo "[$TS] session=$SESSION_ID pattern=$pattern detail=\"$detail\" recipe=\"$recipe\"" >> "$LOG_PATH"
  DETECTIONS="${DETECTIONS}"$'\n'"- $pattern: $detail → $recipe"
}

# --- Pattern: repeated-tool-call ---
if is_enabled "repeated-tool-call"; then
  REPEATED=$(jq -r 'select(.type == "tool_use") | select(.name == "Bash" or .name == "Read" or .name == "Grep") | "\(.name):\(.input.command // .input.file_path // .input.pattern // "")"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | tail -n "$REPEATED_WINDOW" \
    | sort | uniq -c | sort -rn | awk -v t="$REPEATED_COUNT" '$1 >= t {print $0; exit}')
  if [ -n "$REPEATED" ]; then
    CMD=$(echo "$REPEATED" | sed -E 's/^ *[0-9]+ *//')
    emit "repeated-tool-call" "$CMD" "Loop detected on '$CMD'. Try a different approach (different command, different file, ask user)."
  fi
fi

# --- Pattern: edit-mismatch ---
if is_enabled "edit-mismatch"; then
  EDIT_FAIL_COUNT=$(jq -r 'select(.type == "tool_result" and .name == "Edit") | .content // ""' "$TRANSCRIPT_PATH" 2>/dev/null \
    | grep -c "old_string not found" || true)
  if [ "$EDIT_FAIL_COUNT" -ge "$EDIT_MISMATCH_COUNT" ]; then
    BAD_FILE=$(jq -r 'select(.type == "tool_use" and .name == "Edit") | .input.file_path // ""' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
    emit "edit-mismatch" "$EDIT_FAIL_COUNT failed Edits on $BAD_FILE" "Re-Read $BAD_FILE before next Edit — context is stale."
  fi
fi

# --- Pattern: stale-read ---
if is_enabled "stale-read"; then
  STALE_FILE=$(jq -rn '
    [
      foreach inputs as $row (
        {turn: 0, reads: {}, writes_since: {}, stale: null};
        if $row.type == "tool_use" then
          .turn += 1
          | if $row.name == "Read" and $row.input.file_path then
              .reads[$row.input.file_path] = .turn
              | .writes_since[$row.input.file_path] = false
            elif ($row.name == "Write") and $row.input.file_path then
              if .reads[$row.input.file_path] then .writes_since[$row.input.file_path] = true else . end
            elif $row.name == "Edit" and $row.input.file_path then
              if .reads[$row.input.file_path] and .writes_since[$row.input.file_path] then
                .stale = $row.input.file_path
              else . end
            else . end
        else . end;
        .
      )
    ] | last | .stale // empty
  ' < "$TRANSCRIPT_PATH" 2>/dev/null || true)
  if [ -n "$STALE_FILE" ]; then
    emit "stale-read" "$STALE_FILE" "Re-read $STALE_FILE — modified since last Read."
  fi
fi

# --- Pattern: recovery-spiral ---
if is_enabled "recovery-spiral"; then
  SPIRAL=$(jq -rn --argjson n "$SPIRAL_COUNT" '
    [
      foreach inputs as $row (
        {seen: {}, streak: 0, hit: false};
        if $row.type == "tool_use" then
          ($row.input.file_path // "" | tostring) as $fp |
          if $row.name == "Read" and .seen[$fp] then
            .streak += 1
            | if .streak >= $n then .hit = true else . end
          else
            (if $row.name == "Read" and $fp != "" then .seen[$fp] = true else . end)
            | .streak = 0
          end
        else . end;
        .
      )
    ] | last | .hit
  ' < "$TRANSCRIPT_PATH" 2>/dev/null || echo "false")
  if [ "$SPIRAL" = "true" ]; then
    emit "recovery-spiral" "$SPIRAL_COUNT+ consecutive re-Reads of previously-seen files" "Recovery spiral detected. Run /clear, paste handoff Resume prompt, continue."
  fi
fi

# --- Pattern: instruction-fade ---
# Heuristic: same first 80 chars of a user message repeated 2+ times within last 10 turns
if is_enabled "instruction-fade"; then
  REPEATED_USER=$(jq -r 'select(.type == "user") |
    ([.content] | flatten | map(if type == "object" then (.text // .content // (. | tostring)) else (. | tostring) end) | add // "" | .[0:80])' "$TRANSCRIPT_PATH" 2>/dev/null \
    | tail -10 | sort | uniq -c | sort -rn | awk '$1 >= 2 {print $0; exit}')
  if [ -n "$REPEATED_USER" ]; then
    INSTR=$(echo "$REPEATED_USER" | sed -E 's/^ *[0-9]+ *//')
    emit "instruction-fade" "$INSTR" "Claude appears to be missing instruction: \"$INSTR\". Consider re-stating in a fresh session (handoff RECOVER)."
  fi
fi

# --- Pattern: context-drowning ---
# Heuristic: any tool_result >10KB in the transcript
if is_enabled "context-drowning"; then
  LARGE=$(jq -r 'select(.type == "tool_result") |
    ([.content] | flatten | map(if type == "object" then (.text // .content // (. | tostring)) else (. | tostring) end) | add // "" | length) as $len |
    "\(.name // ""):\($len)"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | awk -F: '$2 > 10240 {print $0; exit}')
  if [ -n "$LARGE" ]; then
    emit "context-drowning" "$LARGE" "Large tool output detected. For next big read, consider subagent dispatch instead of inlining."
  fi
fi

# Emit additionalContext if any pattern matched
if [ -n "$DETECTIONS" ]; then
  jq -n --arg ctx "Detected failure pattern(s) this session:$DETECTIONS\n\nSee $LOG_PATH for the full log." '{
    hookSpecificOutput: {
      hookEventName: "Stop",
      additionalContext: $ctx
    }
  }'
fi

exit 0
