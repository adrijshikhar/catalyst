#!/usr/bin/env bash
# UserPromptSubmit-session-health.sh — Catalyst session-health (per-turn)
#
# Event:   UserPromptSubmit
# Purpose: Reads the transcript on every user prompt, runs 4 per-turn signals
#          (context-pressure counts as one signal surfaced at 2 levels) via the
#          shared session-health-signals library, and emits ONE additionalContext
#          alert at the most urgent level (single-alert bar).
#          Appends one line per alert to .claude/session-health.log.
#
# Signals (urgency order, highest → lowest; context-pressure = one signal, 2 levels):
#   1. context-pressure STRONG  — token count ≥ 0.70×effective window
#   1. context-pressure WARN     — token count ≥ 0.50×effective window
#   2. contradiction   — last assistant turn contradicts PROJECT_STATE.md
#   3. stale-read      — Edit on file F where last Read was >15 tool-use events ago
#   4. repeated-tool   — same tool call ×3 in last 5 turns
#
# Exit codes:
#   0   — done; stdout is hook JSON (or empty when no signal fires)
#   1   — infra error (jq missing, lib missing); fail-open: Claude Code ignores hook
#
# Config:
#   .claude/session-health-watch.json  (optional; falls back to built-in defaults)
#   CATALYST_SH_ADVERTISED_TOKENS      env var — effective window base (default 200000)
#   CATALYST_TIKTOKEN=1                enable tiktoken-based token counting
#   CATALYST_SH_EFFECTIVE_FRAC         effective window fraction (default 0.70)
#   CATALYST_SH_WARN_FRAC              warn threshold fraction of effective (default 0.50)
#   CATALYST_SH_STRONG_FRAC            strong threshold fraction of effective (default 0.70)

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
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  # No transcript yet (fresh session) — emit nothing
  exit 0
fi

# ── Load config ───────────────────────────────────────────────────────────────
CONFIG_FILE="$PROJECT_DIR/.claude/session-health-watch.json"
REPEAT_COUNT=3
REPEAT_WINDOW=5
STALE_TURNS=15
CHECK_CONTRADICTION=1
LOG_PATH="$PROJECT_DIR/.claude/session-health.log"

if [ -f "$CONFIG_FILE" ]; then
  {
    REPEAT_COUNT=$(jq -r '.repeated_tool_call_count // 3' "$CONFIG_FILE" || echo 3)
    REPEAT_WINDOW=$(jq -r '.repeated_tool_call_window_turns // 5' "$CONFIG_FILE" || echo 5)
    STALE_TURNS=$(jq -r '.stale_read_max_turns // 15' "$CONFIG_FILE" || echo 15)
    CHECK_CONTRADICTION=$(jq -r '.check_contradiction_with_project_state // true | if . then 1 else 0 end' "$CONFIG_FILE" || echo 1)
    RAW_LOG=$(jq -r --arg d "$PROJECT_DIR/.claude/session-health.log" '.log_path // $d' "$CONFIG_FILE" || echo "$PROJECT_DIR/.claude/session-health.log")
    # Clamp log path inside PROJECT_DIR (hook convention: never write outside project dir).
    case "$RAW_LOG" in
      *..*) LOG_PATH="$PROJECT_DIR/.claude/session-health.log" ;;
      "$PROJECT_DIR"/*) LOG_PATH="$RAW_LOG" ;;
      *) LOG_PATH="$PROJECT_DIR/.claude/session-health.log" ;;
    esac
  } || true
fi

# ── Signal 1 + 2: context level ───────────────────────────────────────────────
USED_TOKENS=$(sh_count_tokens "$TRANSCRIPT_PATH")
CTX_LEVEL=$(sh_classify "$USED_TOKENS")

# Compute effective window and thresholds for the alert message
EFF_WIN=$(sh_effective_window)
WARN_TOK=$(sh_warn_threshold)
STRONG_TOK=$(sh_strong_threshold)

# ── Signal 3: contradiction with PROJECT_STATE.md ─────────────────────────────
CONTRADICTION_TEXT=""
PROJECT_STATE="$PROJECT_DIR/.claude/PROJECT_STATE.md"
if [ "$CHECK_CONTRADICTION" = "1" ]; then
  CONTRADICTION_TEXT=$(sh_detect_contradiction "$TRANSCRIPT_PATH" "$PROJECT_STATE")
fi

# ── Signal 4: stale read ─────────────────────────────────────────────────────
STALE_FILE=$(sh_detect_stale_read "$TRANSCRIPT_PATH" "$STALE_TURNS")

# ── Signal 5: repeated tool call ─────────────────────────────────────────────
REPEATED_RESULT=$(sh_detect_repeated_tool "$TRANSCRIPT_PATH" "$REPEAT_COUNT" "$REPEAT_WINDOW")
REPEATED_KEY=""
REPEATED_CNT=0
if [ -n "$REPEATED_RESULT" ]; then
  # sh_detect_repeated_tool echoes "KEY COUNT" (space-separated)
  REPEATED_CNT=$(printf '%s' "$REPEATED_RESULT" | awk '{print $NF}')
  REPEATED_KEY=$(printf '%s' "$REPEATED_RESULT" | awk '{$NF=""; sub(/ $/, ""); print}')
fi

# ── Decide most urgent alert (single-alert bar) ───────────────────────────────
ALERT=""

if [ "$CTX_LEVEL" = "strong" ]; then
  ALERT="CONTEXT STRONG: transcript is ~${USED_TOKENS} tokens (effective window ${EFF_WIN} tok; strong threshold ${STRONG_TOK} tok). Context critically full — run /catalyst:handoff reground NOW before continuing, or /catalyst:handoff split if this session has braided multiple threads."
elif [ "$CTX_LEVEL" = "warn" ]; then
  ALERT="CONTEXT WARN: transcript is ~${USED_TOKENS} tokens (effective window ${EFF_WIN} tok; warn threshold ${WARN_TOK} tok). Approaching the effective context limit — run /catalyst:handoff reground to re-ground, or /catalyst:handoff split if this session has braided multiple threads."
elif [ -n "$CONTRADICTION_TEXT" ]; then
  ALERT="CONTRADICTION: $CONTRADICTION_TEXT. Verify against .claude/PROJECT_STATE.md before proceeding."
elif [ -n "$STALE_FILE" ]; then
  ALERT="STALE READ: most recent Edit on '$STALE_FILE' followed a Read >${STALE_TURNS} tool-use events ago. Re-Read '$STALE_FILE' before further edits to avoid old_string mismatch."
elif [ -n "$REPEATED_RESULT" ] && [ "$REPEATED_CNT" -ge "$REPEAT_COUNT" ]; then
  ALERT="REPEATED TOOL CALL: '$REPEATED_KEY' ran ${REPEATED_CNT} times in last ${REPEAT_WINDOW} turns. Try a different approach (different command, different file, or ask user)."
fi

# ── Emit hook output + append to log ─────────────────────────────────────────
if [ -n "$ALERT" ]; then
  mkdir -p "$(dirname "$LOG_PATH")"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '[%s] %s\n' "$TS" "$ALERT" >> "$LOG_PATH"
  jq -n --arg msg "$ALERT" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
fi

exit 0
