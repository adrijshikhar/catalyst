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
# CATALYST_TIKTOKEN              (default: unset)
#   Set to "1" to use the tiktoken Python package for exact token counting
#   instead of the char-count heuristic (chars ÷ 4). Requires Python +
#   tiktoken to be installed; falls back to heuristic silently if unavailable.
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
#     sh_detect_contradiction <transcript> <project_state_file>
#       → echo "<contradiction description>" if detected, else empty
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
# Estimates token count. Uses tiktoken when CATALYST_TIKTOKEN=1 and tiktoken
# is importable; otherwise falls back to chars÷4 heuristic.
sh_count_tokens() {
  local transcript_file="$1"
  [ -f "$transcript_file" ] || { echo "0"; return 0; }
  if [ "${CATALYST_TIKTOKEN:-0}" = "1" ] && python3 -c "import tiktoken" 2>/dev/null; then
    python3 -c "
import tiktoken, sys, os
try:
    enc = tiktoken.get_encoding('cl100k_base')
    data = open(sys.argv[1]).read()
    print(len(enc.encode(data)))
except Exception:
    chars = os.path.getsize(sys.argv[1])
    print((chars + 3) // 4)
" "$transcript_file" 2>/dev/null || echo "0"
  else
    local total_chars
    total_chars=$(wc -c < "$transcript_file" 2>/dev/null | tr -d ' ' || echo "0")
    echo $(( (total_chars + 3) / 4 ))
  fi
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
  recent_tool_uses=$(jq -c 'select(.type=="tool_use") | {name, input: (.input | tostring)}' "$transcript" 2>/dev/null \
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

  jq -rs --argjson stale "$stale_turns" '
    [ .[] | select(.type=="tool_use") ] | to_entries
    | (map(select(.value.name=="Edit" and ((.value.input.file_path // "") != ""))) | last) as $edit
    | if $edit == null then empty
      else ($edit.value.input.file_path) as $f
        | (map(select(.value.name=="Read"
              and ((.value.input.file_path // "") == $f)
              and (.key < $edit.key))) | last) as $read
        | if ($read != null) and (($edit.key - $read.key) > $stale) then $f else empty end
      end
  ' "$transcript" 2>/dev/null | tail -1 || echo ""
}

# sh_detect_contradiction <transcript_file> <project_state_file>
# Checks the most recent assistant message against "Decision: use X not Y"
# lines in project_state_file. Prints a description if contradiction found,
# empty otherwise. Uses POSIX sed with BSD and GNU word-boundary fallbacks.
sh_detect_contradiction() {
  local transcript="$1"
  local project_state="$2"

  if [ ! -f "$project_state" ]; then
    return 0
  fi

  local last_assistant
  last_assistant=$(jq -r 'select(.type=="assistant") | .content // empty' "$transcript" 2>/dev/null | tail -1)

  if [ -z "$last_assistant" ]; then
    return 0
  fi

  local result=""
  while IFS= read -r decision; do
    # Extract "not X" (BSD word-boundary first, GNU fallback)
    local not_part
    not_part=$(echo "$decision" | sed -n 's/.*[[:<:]]not[[:space:]]\{1,\}\([a-zA-Z][a-zA-Z _]*\).*/\1/p' 2>/dev/null | head -1 | tr -d '\n')
    if [ -z "$not_part" ]; then
      not_part=$(echo "$decision" | sed -n 's/.*\bnot[[:space:]]\{1,\}\([a-zA-Z][a-zA-Z _]*\).*/\1/p' 2>/dev/null | head -1 | tr -d '\n')
    fi

    # Extract "use X not" (BSD word-boundary first, GNU fallback)
    local use_part
    use_part=$(echo "$decision" | sed -n 's/.*[[:<:]]use[[:space:]]\{1,\}\([a-zA-Z][a-zA-Z _]*\)[[:space:]]\{1,\}not.*/\1/p' 2>/dev/null | head -1 | tr -d '\n')
    if [ -z "$use_part" ]; then
      use_part=$(echo "$decision" | sed -n 's/.*\buse[[:space:]]\{1,\}\([a-zA-Z][a-zA-Z _]*\)[[:space:]]\{1,\}not.*/\1/p' 2>/dev/null | head -1 | tr -d '\n')
    fi

    if [ -n "$not_part" ] && [ -n "$use_part" ]; then
      if echo "$last_assistant" | grep -qiF "$not_part" && ! echo "$last_assistant" | grep -qiF "$use_part"; then
        result="contradicts PROJECT_STATE decision: '$decision' (chat mentions '$not_part', should be '$use_part')"
        break
      fi
    fi
  done < <(grep -h "^Decision:" "$project_state" 2>/dev/null || echo "")

  echo "$result"
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
  result=$(jq -r 'select(.type == "tool_use") | select(.name == "Bash" or .name == "Read" or .name == "Grep") | "\(.name):\(.input.command // .input.file_path // .input.pattern // "")"' \
    "$transcript" 2>/dev/null \
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
  fail_count=$(jq -r 'select(.type == "tool_result") | .content // ""' \
    "$transcript" 2>/dev/null \
    | grep -c "old_string not found" || true)

  if [ "$fail_count" -ge "$mismatch_threshold" ]; then
    local bad_file
    bad_file=$(jq -r 'select(.type == "tool_use" and .name == "Edit") | .input.file_path // ""' \
      "$transcript" 2>/dev/null | tail -1)
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
  stale_file=$(jq -rn '
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
  ' < "$transcript" 2>/dev/null || true)

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
  result=$(jq -rn --argjson n "$spiral_count" '
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
  ' < "$transcript" 2>/dev/null || echo "false")

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
# Heuristic: any tool_result whose content exceeds 10KB (10240 chars).
# Ported from failure-pattern-detector v0.5.
# Prints "TOOL_NAME:SIZE" on match; returns 0 on match, 1 otherwise.
sh_pattern_context_drowning() {
  local transcript="$1"

  local large
  large=$(jq -r 'select(.type == "tool_result") |
    ([.content] | flatten | map(if type == "object" then (.text // .content // (. | tostring)) else (. | tostring) end) | add // "" | length) as $len |
    "\(.name // ""):\($len)"' "$transcript" 2>/dev/null \
    | awk -F: '$2 > 10240 {print $0; exit}' || echo "")

  if [ -n "$large" ]; then
    echo "$large"
    return 0
  fi
  return 1
}
