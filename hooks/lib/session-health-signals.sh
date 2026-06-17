# hooks/lib/session-health-signals.sh — Catalyst session-health shared signal library
#
# Sourced by two session-health hooks:
#   - hooks/UserPromptSubmit-session-health.sh  (per-turn degradation signals)
#   - hooks/Stop-session-health.sh              (session-end failure-pattern matchers)
#
# Do NOT execute directly. Source with:
#   . "$(dirname "$0")/lib/session-health-signals.sh"
#
# Callers set their own 'set -euo pipefail' before sourcing. This file does NOT
# set shell options — it is a pure sourced library (no shebang, no set).
#
# ── ENV CONFIG READ BY THIS LIBRARY ──────────────────────────────────────────
#
# CATALYST_SH_ADVERTISED_TOKENS  (default: 200000)
#   The model's advertised context window in tokens.
#
# CATALYST_SH_EFFECTIVE_FRAC     (default: 0.70)
#   Fraction of the advertised window that is actually usable before
#   quality degrades. Effective window = advertised × effective_frac.
#
# CATALYST_SH_WARN_FRAC          (default: 0.50)
#   Fraction of the *effective* window at which a WARN alert is emitted.
#   WARN threshold (tok) = advertised × effective_frac × warn_frac.
#   At defaults: 200000 × 0.70 × 0.50 = 70000 tokens.
#
# CATALYST_SH_STRONG_FRAC        (default: 0.70)
#   Fraction of the *effective* window at which a STRONG alert is emitted.
#   STRONG threshold (tok) = advertised × effective_frac × strong_frac.
#   At defaults: 200000 × 0.70 × 0.70 = 98000 tokens.
#
#
# ── FUNCTION INVENTORY ───────────────────────────────────────────────────────
#
#   Token / context helpers (per-turn):
#     sh_count_tokens <file>           → echo <approx_token_count>
#     sh_effective_window              → echo <effective_window_tokens>
#     sh_warn_threshold                → echo <warn_threshold_tokens>
#     sh_strong_threshold              → echo <strong_threshold_tokens>
#     sh_classify <token_count>        → echo none|warn|strong
#
#   Per-turn signal detectors (UserPromptSubmit):
#     sh_detect_repeated_tool <transcript> <count> <window>
#       → echo "KEY COUNT" if detected, else empty
#     sh_detect_stale_read <transcript> <stale_turns>
#       → echo "<file_path>" if detected, else empty
#
#   Session-end pattern matchers (Stop) — each returns 0 if pattern found,
#   non-zero if not; detail echoed on stdout:
#     sh_pattern_repeated_tool <transcript> <count> <window>
#       → echo "CMD COUNT" on match
#     sh_pattern_edit_mismatch <transcript> <mismatch_count>
#       → echo "<detail>" on match
#     sh_pattern_stale_read_stop <transcript>
#       → echo "<file_path>" on match
#     sh_pattern_recovery_spiral <transcript> <spiral_count>
#       → echo "true" on match
#     sh_pattern_instruction_fade <transcript>
#       → echo "<instruction snippet>" on match
#     sh_pattern_context_drowning <transcript>
#       → echo "<tool:size>" on match
#
# ─────────────────────────────────────────────────────────────────────────────

# Shared transcript reader (real .message.content[] shape). Sourced by callers
# too, but guard against double-source.
if ! declare -f sh_normalize_transcript >/dev/null 2>&1; then
  _SH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  . "$_SH_LIB_DIR/transcript.sh" 2>/dev/null || true
fi

# ── Internal: read effective-window config from env ───────────────────────────

_sh_advertised_tokens() {
  local adv="${CATALYST_SH_ADVERTISED_TOKENS:-200000}"
  # Guard: treat empty, non-numeric, or non-positive values as the default.
  # A non-numeric value (e.g. "abc") would otherwise slip past `[ -le 0 ]`
  # (which errors and is silenced) and then abort downstream `$(( adv * ... ))`
  # under `set -u`, silently suppressing all context alerts.
  case "$adv" in
    ''|*[!0-9]*) adv=200000 ;;
  esac
  [ "$adv" -le 0 ] 2>/dev/null && adv=200000
  echo "$adv"
}

# Pattern detection window: number of most-recent tool events Stop matchers scan.
# Scoping to recent activity prevents long/compacted sessions from tripping
# patterns on old, already-resolved churn.
_sh_pattern_window() {
  local w="${CATALYST_SH_PATTERN_WINDOW:-100}"
  case "$w" in ''|*[!0-9]*) w=100 ;; esac
  [ "$w" -le 0 ] 2>/dev/null && w=100
  echo "$w"
}

# sh_recent_tool_events <transcript> [n] — last n normalized tool events.
sh_recent_tool_events() {
  local transcript="$1"
  local n="${2:-$(_sh_pattern_window)}"
  sh_normalize_transcript "$transcript" | tail -n "$n"
}

_sh_effective_frac_pct() {
  # Returns integer percentage (0-100) to avoid floating point in POSIX sh.
  # CATALYST_SH_EFFECTIVE_FRAC is a decimal like "0.70"; convert to int pct.
  local frac="${CATALYST_SH_EFFECTIVE_FRAC:-0.70}"
  # Multiply by 100 via awk using -v to prevent shell injection.
  awk -v f="$frac" 'BEGIN { printf "%d", f * 100 }'
}

_sh_warn_frac_pct() {
  local frac="${CATALYST_SH_WARN_FRAC:-0.50}"
  awk -v f="$frac" 'BEGIN { printf "%d", f * 100 }'
}

_sh_strong_frac_pct() {
  local frac="${CATALYST_SH_STRONG_FRAC:-0.70}"
  awk -v f="$frac" 'BEGIN { printf "%d", f * 100 }'
}

# ── Token counting ────────────────────────────────────────────────────────────

# sh_count_tokens <transcript_file>
# Returns the context size from the LAST assistant turn's .message.usage:
#   input_tokens + cache_read_input_tokens + cache_creation_input_tokens
# (output_tokens excluded — they don't consume the input context window)
# Returns 0 when no usage field is present (caller treats 0 as "suppress").
# Fails-open: returns 0 when jq is absent or the file is unreadable.
# NOTE: CATALYST_TIKTOKEN no longer affects this signal; tiktoken counted
# transcript-FILE bytes (over-counted to tens of millions after compaction).
sh_count_tokens() {
  local transcript_file="$1"
  [ -f "$transcript_file" ] || { echo "0"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "0"; return 0; }
  jq -s '
    [ .[] | select((.message.usage // .usage) != null) ] | last
    | (.message.usage // .usage)
    | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
    // 0
  ' "$transcript_file" 2>/dev/null || echo "0"
}

# ── Threshold computation ─────────────────────────────────────────────────────

# sh_effective_window
# Returns: effective_window = advertised × effective_frac (integer tokens)
sh_effective_window() {
  local adv
  adv=$(_sh_advertised_tokens)
  local eff_pct
  eff_pct=$(_sh_effective_frac_pct)
  echo $(( adv * eff_pct / 100 ))
}

# sh_warn_threshold
# Returns: warn_threshold = effective_window × warn_frac (integer tokens)
sh_warn_threshold() {
  local eff
  eff=$(sh_effective_window)
  local warn_pct
  warn_pct=$(_sh_warn_frac_pct)
  echo $(( eff * warn_pct / 100 ))
}

# sh_strong_threshold
# Returns: strong_threshold = effective_window × strong_frac (integer tokens)
sh_strong_threshold() {
  local eff
  eff=$(sh_effective_window)
  local strong_pct
  strong_pct=$(_sh_strong_frac_pct)
  echo $(( eff * strong_pct / 100 ))
}

# sh_classify <token_count>
# Prints: none | warn | strong
# none   → token_count < warn_threshold
# warn   → warn_threshold ≤ token_count < strong_threshold
# strong → token_count ≥ strong_threshold
sh_classify() {
  local tokens="$1"
  local warn_tok
  warn_tok=$(sh_warn_threshold)
  local strong_tok
  strong_tok=$(sh_strong_threshold)
  if [ "$tokens" -ge "$strong_tok" ]; then
    echo "strong"
  elif [ "$tokens" -ge "$warn_tok" ]; then
    echo "warn"
  else
    echo "none"
  fi
}

# ── Per-turn signal detectors (UserPromptSubmit) ──────────────────────────────

# sh_detect_repeated_tool <transcript_file> <repeat_count> <window_turns>
# Detects when the same tool call (name + input) appears ≥ repeat_count times
# within the last window_turns tool_use entries.
# Prints "TOOL_KEY COUNT" if detected, empty otherwise.
sh_detect_repeated_tool() {
  local transcript="$1"
  local repeat_count="${2:-3}"
  local window="${3:-5}"

  local recent_tool_uses
  recent_tool_uses=$(sh_normalize_transcript "$transcript" | jq -c 'select(.type=="tool_use") | {name, input: (.input | tostring)}' 2>/dev/null \
    | tail -n "$window" || echo "")

  if [ -z "$recent_tool_uses" ]; then
    return 0
  fi

  local most_frequent
  most_frequent=$(echo "$recent_tool_uses" | sort | uniq -c | sort -rn | head -1 2>/dev/null || echo "")

  if [ -z "$most_frequent" ]; then
    return 0
  fi

  local found_count
  found_count=$(echo "$most_frequent" | awk '{print $1}')

  if [ "$found_count" -ge "$repeat_count" ] && [ "$found_count" -gt 0 ]; then
    local key
    key=$(echo "$most_frequent" | sed 's/^ *[0-9]* *//' \
      | jq -r '"\(.name):\(.input | fromjson | .command // .file_path // .pattern // "?")"' 2>/dev/null \
      || echo "?")
    echo "$key $found_count"
  fi
}

# sh_detect_stale_read <transcript_file> <stale_turns>
# Detects when an Edit on file F follows the last Read of F by more than
# stale_turns tool_use events (position-based ordinal, not wall-clock turns).
# Prints the file path if detected, empty otherwise.
sh_detect_stale_read() {
  local transcript="$1"
  local stale_turns="${2:-15}"

  sh_normalize_transcript "$transcript" | jq -rs --argjson stale "$stale_turns" '
    [ .[] | select(.type=="tool_use") ] | to_entries
    | (map(select(.value.name=="Edit" and ((.value.input.file_path // "") != ""))) | last) as $edit
    | if $edit == null then empty
      else ($edit.value.input.file_path) as $f
        | (map(select(.value.name=="Read"
              and ((.value.input.file_path // "") == $f)
              and (.key < $edit.key))) | last) as $read
        | if ($read != null) and (($edit.key - $read.key) > $stale) then $f else empty end
      end
  ' 2>/dev/null | tail -1 || echo ""
}

# ── Session-end failure-pattern matchers (Stop hook) ─────────────────────────

# sh_pattern_repeated_tool <transcript_file> <count_threshold> <window_turns>
# Stop-hook variant: checks Bash/Read/Grep calls only (session-end scope,
# ported from failure-pattern-detector v0.5).
# Prints "CMD COUNT" on match; returns 0 on match, 1 otherwise.
sh_pattern_repeated_tool() {
  local transcript="$1"
  local count_threshold="${2:-3}"
  local window="${3:-5}"

  local result
  result=$(sh_recent_tool_events "$transcript" | jq -r 'select(.type == "tool_use") | select(.name == "Bash" or .name == "Read" or .name == "Grep") | "\(.name):\(.input.command // .input.file_path // .input.pattern // "")"' \
    2>/dev/null \
    | tail -n "$window" \
    | sort | uniq -c | sort -rn \
    | awk -v t="$count_threshold" '$1 >= t {print $0; exit}' || echo "")

  if [ -n "$result" ]; then
    local cmd
    cmd=$(echo "$result" | sed -E 's/^ *[0-9]+ *//')
    local cnt
    cnt=$(echo "$result" | awk '{print $1}')
    echo "$cmd $cnt"
    return 0
  fi
  return 1
}

# sh_pattern_edit_mismatch <transcript_file> <mismatch_count_threshold>
# Detects ≥ mismatch_count "old_string not found" errors in tool results.
# Prints "<N> failed Edits on <file>" on match; returns 0 on match, 1 otherwise.
sh_pattern_edit_mismatch() {
  local transcript="$1"
  local mismatch_threshold="${2:-2}"

  local fail_count
  # tool_result rows carry no `.name` field (only content + type), so the old
  # `.name == "Edit"` selector matched nothing and this detector never fired.
  # "old_string not found" appears only in Edit results, so scanning all
  # tool_result content is both correct and sufficient.
  fail_count=$(sh_normalize_transcript "$transcript" | jq -r 'select(.type == "tool_result") | .content // ""' \
    2>/dev/null \
    | grep -c "old_string not found" || true)

  if [ "$fail_count" -ge "$mismatch_threshold" ]; then
    local bad_file
    bad_file=$(sh_normalize_transcript "$transcript" | jq -r 'select(.type == "tool_use" and .name == "Edit") | .input.file_path // ""' \
      2>/dev/null | tail -1)
    echo "$fail_count failed Edits on $bad_file"
    return 0
  fi
  return 1
}

# sh_pattern_stale_read_stop <transcript_file>
# Stop-hook variant: detects the Write-between-Read-and-Edit stale pattern
# (distinct from the per-turn gap-count stale-read in sh_detect_stale_read).
# Ported from failure-pattern-detector v0.5.
# Prints the file path on match; returns 0 on match, 1 otherwise.
sh_pattern_stale_read_stop() {
  local transcript="$1"

  local stale_file
  stale_file=$(sh_recent_tool_events "$transcript" | jq -rn '
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
  ' 2>/dev/null || true)

  if [ -n "$stale_file" ]; then
    echo "$stale_file"
    return 0
  fi
  return 1
}

# sh_pattern_recovery_spiral <transcript_file> <spiral_count>
# Detects ≥ spiral_count consecutive re-Reads of previously-seen files.
# Prints "true" on match; returns 0 on match, 1 otherwise.
sh_pattern_recovery_spiral() {
  local transcript="$1"
  local spiral_count="${2:-3}"

  local result
  result=$(sh_recent_tool_events "$transcript" | jq -rn --argjson n "$spiral_count" '
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
  ' 2>/dev/null || echo "false")

  if [ "$result" = "true" ]; then
    echo "true"
    return 0
  fi
  return 1
}

# sh_pattern_instruction_fade <transcript_file>
# Heuristic: same first 80 chars of a user message repeated ≥ 2 times within
# the last 10 user turns. Ported from failure-pattern-detector v0.5.
# Prints the repeated instruction snippet on match; returns 0 on match, 1 otherwise.
sh_pattern_instruction_fade() {
  local transcript="$1"

  local repeated_user
  repeated_user=$(jq -r 'select(.type == "user") |
    ([.content] | flatten | map(if type == "object" then (.text // .content // "") else (. // "" | tostring) end) | add // "" | .[0:80])
    | select(test("[A-Za-z]") and . != "null")' \
    "$transcript" 2>/dev/null \
    | tail -10 | sort | uniq -c | sort -rn | awk '$1 >= 2 {print $0; exit}' || echo "")

  if [ -n "$repeated_user" ]; then
    local instr
    instr=$(echo "$repeated_user" | sed -E 's/^ *[0-9]+ *//')
    # Guard against empty / literal-"null" snippets (transcripts with many
    # system-injected or empty user turns would otherwise fire on "null").
    if [ -n "$instr" ] && [ "$instr" != "null" ]; then
      echo "$instr"
      return 0
    fi
  fi
  return 1
}

# sh_pattern_context_drowning <transcript_file>
# Heuristic: any tool_result >10KB in the recent window. Prints "<ToolName> result ~<KB>KB".
sh_pattern_context_drowning() {
  local transcript="$1"

  local large
  # Correlate each tool_result with its preceding tool_use (which carries the
  # name) over the recent-events window; report the first >10KB result as
  # "<ToolName> result ~<KB>KB". tool_result itself has no .name.
  large=$(sh_recent_tool_events "$transcript" | jq -rs '
    reduce .[] as $e ({last:"tool", hit:null};
      if $e.type=="tool_use" then .last = ($e.name // "tool")
      elif $e.type=="tool_result" and ((($e.content // "")|length) > 10240) and (.hit==null)
        then .hit = {name:.last, kb: ((($e.content|length)/1024)|floor)}
      else . end)
    | if .hit==null then "" else "\(.hit.name) result ~\(.hit.kb)KB" end
  ' 2>/dev/null || echo "")

  if [ -n "$large" ]; then
    echo "$large"
    return 0
  fi
  return 1
}
