#!/usr/bin/env bash
# Stop-session-health.sh — Catalyst session-health (session-end)
#
# Event:   Stop
# Purpose: Fires when the session ends. Scans the transcript for 6 known
#          failure patterns via the shared session-health-signals library.
#          For each detected pattern, logs a timestamped entry with the
#          session ID, pattern name, detail, and a SPECIFIC recovery recipe.
#          Emits a `systemMessage` with a brief summary if any patterns matched.
#
# Patterns detected (v0.7):
#   - repeated-tool-call   : same Bash/Read/Grep input ≥3× in last 5 turns
#   - edit-mismatch        : ≥2 "old_string not found" errors in transcript
#   - stale-read           : Edit on file F where F was Written between last Read and Edit
#   - recovery-spiral      : ≥3 consecutive re-Reads of previously-seen files
#   - instruction-fade     : same first-80-chars user message repeated ≥2× in last 10 turns
#   - context-drowning     : any tool_result content exceeding 10KB
#
# Exit codes:
#   0   — done (with or without detections); any output is on stdout
#   1   — infra error (jq missing, lib missing); fail-open: Claude Code ignores hook
#
# Config:
#   .claude/session-health.json  (optional; falls back to built-in defaults)
# Log:
#   .claude/session-health.log   (append-only, one line per detection)

set -euo pipefail

# ── Dependency check ─────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  exit 1  # fail-open
fi

# ── Source the shared signal library ─────────────────────────────────────────
SH_LIB="$(dirname "$0")/lib/session-health-signals.sh"
[ -f "$SH_LIB" ] || SH_LIB="$(dirname "$0")/session-health-signals.sh"   # flat-install fallback
# shellcheck source=/dev/null
. "$SH_LIB" 2>/dev/null || exit 0   # fail-open if lib missing

# ── Parse stdin ──────────────────────────────────────────────────────────────
INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# ── Load config ───────────────────────────────────────────────────────────────
CONFIG_FILE="$PROJECT_DIR/.claude/session-health.json"
LOG_PATH="$PROJECT_DIR/.claude/session-health.log"

# Built-in defaults
ENABLED='["repeated-tool-call","edit-mismatch","stale-read","recovery-spiral","instruction-fade","context-drowning"]'
REPEATED_COUNT=3
REPEATED_WINDOW=5
EDIT_MISMATCH_COUNT=2
SPIRAL_COUNT=3

if [ -f "$CONFIG_FILE" ]; then
  {
    ENABLED=$(jq -c '.enabled_patterns // ["repeated-tool-call","edit-mismatch","stale-read","recovery-spiral","instruction-fade","context-drowning"]' "$CONFIG_FILE" || echo '["repeated-tool-call","edit-mismatch","stale-read","recovery-spiral","instruction-fade","context-drowning"]')
    REPEATED_COUNT=$(jq -r '.thresholds.repeated_tool_call_count // 3' "$CONFIG_FILE" || echo 3)
    REPEATED_WINDOW=$(jq -r '.thresholds.repeated_tool_call_window_turns // 5' "$CONFIG_FILE" || echo 5)
    EDIT_MISMATCH_COUNT=$(jq -r '.thresholds.edit_mismatch_count // 2' "$CONFIG_FILE" || echo 2)
    SPIRAL_COUNT=$(jq -r '.thresholds.recovery_spiral_count // 3' "$CONFIG_FILE" || echo 3)
    PATTERN_WINDOW=$(jq -r '.thresholds.pattern_window // empty' "$CONFIG_FILE" 2>/dev/null || true); [ -n "$PATTERN_WINDOW" ] && export CATALYST_SH_PATTERN_WINDOW="$PATTERN_WINDOW"
    RAW_LOG=$(jq -r --arg d "$PROJECT_DIR/.claude/session-health.log" '.log_path // $d' "$CONFIG_FILE" || echo "$PROJECT_DIR/.claude/session-health.log")
    # Clamp log path inside PROJECT_DIR (hook convention).
    case "$RAW_LOG" in
      *..*) LOG_PATH="$PROJECT_DIR/.claude/session-health.log" ;;
      "$PROJECT_DIR"/*) LOG_PATH="$RAW_LOG" ;;
      *) LOG_PATH="$PROJECT_DIR/.claude/session-health.log" ;;
    esac
  } || true
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
is_enabled() {
  local pattern="$1"
  printf '%s' "$ENABLED" | jq -e --arg p "$pattern" 'any(. == $p)' >/dev/null 2>&1
}

mkdir -p "$(dirname "$LOG_PATH")"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DETECTIONS=""

emit() {
  local pattern="$1"
  local detail="$2"
  local recipe="$3"
  printf '[%s] session=%s pattern=%s detail="%s" recipe="%s"\n' \
    "$TS" "$SESSION_ID" "$pattern" "$detail" "$recipe" >> "$LOG_PATH"
  DETECTIONS="${DETECTIONS}"$'\n'"- ${pattern}: ${detail} → ${recipe}"
}

# ── Pattern: repeated-tool-call ───────────────────────────────────────────────
if is_enabled "repeated-tool-call"; then
  REPEAT_RESULT=$(sh_pattern_repeated_tool "$TRANSCRIPT_PATH" "$REPEATED_COUNT" "$REPEATED_WINDOW" || true)
  if [ -n "$REPEAT_RESULT" ]; then
    # sh_pattern_repeated_tool echoes "CMD COUNT" — strip the trailing count for detail
    REPEAT_CMD=$(printf '%s' "$REPEAT_RESULT" | awk '{$NF=""; sub(/ $/, ""); print}')
    emit "repeated-tool-call" \
      "$REPEAT_CMD" \
      "Loop detected on '$REPEAT_CMD'. Try a different approach (different command, different file, ask user)."
  fi
fi

# ── Pattern: edit-mismatch ────────────────────────────────────────────────────
if is_enabled "edit-mismatch"; then
  MISMATCH_RESULT=$(sh_pattern_edit_mismatch "$TRANSCRIPT_PATH" "$EDIT_MISMATCH_COUNT" || true)
  if [ -n "$MISMATCH_RESULT" ]; then
    # Extract the file from the result detail (format: "N failed Edits on <file>")
    BAD_FILE=$(printf '%s' "$MISMATCH_RESULT" | sed 's/.* on //')
    emit "edit-mismatch" \
      "$MISMATCH_RESULT" \
      "Re-Read $BAD_FILE before next Edit — context is stale."
  fi
fi

# ── Pattern: stale-read ───────────────────────────────────────────────────────
if is_enabled "stale-read"; then
  STALE_RESULT=$(sh_pattern_stale_read_stop "$TRANSCRIPT_PATH" || true)
  if [ -n "$STALE_RESULT" ]; then
    emit "stale-read" \
      "$STALE_RESULT" \
      "Re-Read $STALE_RESULT — modified since last Read."
  fi
fi

# ── Pattern: recovery-spiral ──────────────────────────────────────────────────
if is_enabled "recovery-spiral"; then
  SPIRAL_RESULT=$(sh_pattern_recovery_spiral "$TRANSCRIPT_PATH" "$SPIRAL_COUNT" || true)
  if [ "$SPIRAL_RESULT" = "true" ]; then
    emit "recovery-spiral" \
      "${SPIRAL_COUNT}+ consecutive re-Reads of previously-seen files" \
      "Recovery spiral detected. Run /catalyst:handoff reground or /clear and paste handoff Resume prompt to continue in a fresh session."
  fi
fi

# ── Pattern: instruction-fade ─────────────────────────────────────────────────
if is_enabled "instruction-fade"; then
  FADE_RESULT=$(sh_pattern_instruction_fade "$TRANSCRIPT_PATH" || true)
  if [ -n "$FADE_RESULT" ]; then
    emit "instruction-fade" \
      "$FADE_RESULT" \
      "Claude appears to be missing instruction: \"$FADE_RESULT\". Consider re-stating in a fresh session (handoff RECOVER)."
  fi
fi

# ── Pattern: context-drowning ─────────────────────────────────────────────────
if is_enabled "context-drowning"; then
  DROWN_RESULT=$(sh_pattern_context_drowning "$TRANSCRIPT_PATH" || true)
  if [ -n "$DROWN_RESULT" ]; then
    emit "context-drowning" \
      "$DROWN_RESULT" \
      "Large tool output detected ($DROWN_RESULT). For next big read, consider subagent dispatch via /catalyst:handoff reground instead of inlining."
  fi
fi

# ── Surface via systemMessage if any pattern matched ──────────────────────────
# Stop hooks do NOT support hookSpecificOutput.additionalContext (that field is
# UserPromptSubmit/PostToolUse only). The valid non-blocking surface for Stop is
# `systemMessage`. Emitting the wrong shape fails Claude Code's output schema.
if [ -n "$DETECTIONS" ]; then
  WIN=$(_sh_pattern_window)
  jq -n --arg msg "Detected failure pattern(s) in recent activity (last ${WIN} tool calls):${DETECTIONS}"$'\n\n'"See $LOG_PATH for the full log." \
    '{systemMessage: $msg}'
fi

exit 0
