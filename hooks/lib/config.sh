# hooks/lib/config.sh — Catalyst shared config reader + store resolver.
# Sourced, not executed. No shebang, no `set` (the caller owns shell options).
#
#   catalyst_project_root [dir]          -> main-worktree root (parent of the
#                                           shared .git), else dir itself
#   catalyst_store_dir [dir]             -> <root>/.claude/handoffs
#   catalyst_config_get <key> [default]  -> scalar; env > catalyst.json > default
#   catalyst_config_json <key>           -> raw JSON value, or nothing
#
# Env-name rule: CATALYST_ + dotted key uppercased, '.' -> '_'.
# Structured values (arrays/objects) have NO env form and are read only via
# catalyst_config_json — catalyst_config_get returns the default for them
# rather than stringifying a structure.
#
# Fails open: any error yields the default (or nothing for _json) and returns 0.
# This file is the ONE bash home for store resolution — scripts/lint.py fails
# the build if a hook re-inlines `rev-parse --git-common-dir` (P5).

catalyst_project_root() {
  local dir="${1:-$(pwd)}" common
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)
  if [ -n "$common" ]; then
    case "$common" in /*) : ;; *) common="$dir/$common" ;; esac
    common=$(cd "$common" 2>/dev/null && pwd || echo "$common")
    if [ "$(basename "$common")" = ".git" ]; then
      dirname "$common"
      return 0
    fi
  fi
  printf '%s\n' "$dir"
}

catalyst_store_dir() {
  printf '%s/.claude/handoffs\n' "$(catalyst_project_root "${1:-$(pwd)}")"
}

_catalyst_config_file() {
  printf '%s/.claude/catalyst.json\n' \
    "$(catalyst_project_root "${CLAUDE_PROJECT_DIR:-$(pwd)}")"
}

_catalyst_env_name() {
  printf 'CATALYST_%s\n' \
    "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr '.' '_')"
}

catalyst_config_get() {
  local key="$1" def="${2-}" name val cfg
  name=$(_catalyst_env_name "$key")
  val="${!name-}"
  if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
  cfg=$(_catalyst_config_file)
  if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
    val=$(jq -r --arg k "$key" '
      getpath($k | split("."))
      | if . == null then empty
        elif type == "string" or type == "number" or type == "boolean" then tostring
        else empty end' "$cfg" 2>/dev/null || true)
    if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
  fi
  printf '%s\n' "$def"
}

catalyst_config_json() {
  local key="$1" cfg
  cfg=$(_catalyst_config_file)
  [ -f "$cfg" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # `getpath(...) // empty` treats a JSON `false` leaf as falsy, so it would
  # be indistinguishable from an absent key — the Python twin's get_json()
  # correctly returns False for that leaf. Use an explicit null check instead
  # so absent (null) is the only thing that yields no output.
  jq -c --arg k "$key" 'getpath($k | split(".")) | if . == null then empty else . end' "$cfg" 2>/dev/null || return 0
}

# catalyst_config_enabled <dotted.key> — 0 (enabled) unless the resolved value
# is explicitly falsy. THE only falsy-check in the codebase: a hook that spells
# out its own `false|0|no|off` case is duplicating load-bearing parsing (P5).
# Defaults to enabled, including when the config is missing or unreadable, so a
# typo cannot silently switch the plugin's own behavior off.
catalyst_config_enabled() {
  case "$(catalyst_config_get "$1" true | tr '[:upper:]' '[:lower:]')" in
    false|0|no|off) return 1 ;;
    *)              return 0 ;;
  esac
}
