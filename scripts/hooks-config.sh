#!/usr/bin/env bash
# scripts/hooks-config.sh — report and toggle Catalyst's own hooks.
#
# Hooks are registered by hooks/hooks.json and always run from the plugin
# cache, so there is nothing to install and nothing to drift. What a user can
# change is whether the two ADVISORY hooks act; that lives in
# .claude/catalyst.json, which is the only state. This script is a front door
# onto that file, not a second source of truth.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/config.sh"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CFG="$(catalyst_project_root "$PROJECT_DIR")/.claude/catalyst.json"

# hook alias -> config key
key_for() {
  case "$1" in
    precompact)   echo "hooks.precompact_prompt" ;;
    sessionstart) echo "hooks.sessionstart_resume" ;;
    *)
      echo "ERROR: unknown hook '$1'. Use precompact or sessionstart." >&2
      return 2 ;;
  esac
}

set_key() { # <dotted.key> <true|false>
  local key="$1" val="$2"
  mkdir -p "$(dirname "$CFG")"
  [ -f "$CFG" ] || printf '%s' '{}' > "$CFG"
  if ! jq --argjson v "$val" --arg k "${key#hooks.}" \
       '.hooks //= {} | .hooks[$k] = $v' "$CFG" > "$CFG.tmp"; then
    rm -f "$CFG.tmp"
    echo "ERROR: could not update $CFG — is it valid JSON? Nothing was changed." >&2
    return 1
  fi
  if ! mv "$CFG.tmp" "$CFG"; then
    rm -f "$CFG.tmp"
    echo "ERROR: could not write $CFG. Nothing was changed." >&2
    return 1
  fi
  echo "Set $key = $val in $CFG"
}

case "${1:-status}" in
  status)
    echo "Catalyst hooks"
    echo
    printf '%-30s %-14s %-12s %s\n' "HOOK" "EVENT" "MATCHER" "STATE"
    for row in "PreCompact-handoff-write.sh PreCompact  ''  hooks.precompact_prompt" \
               "SessionStart-handoff-read.sh SessionStart  ''  hooks.sessionstart_resume"; do
      # shellcheck disable=SC2086  # intentional word split over the row fields
      set -- $row
      state="always on"
      if [ "$4" != "-" ]; then
        if catalyst_config_enabled "$4"; then state="enabled"; else state="disabled"; fi
      fi
      printf '%-30s %-14s %-12s %s\n' "$1" "$2" "$3" "$state"
    done
    echo
    echo "Registered by hooks/hooks.json — they run from the plugin, so there is nothing to install."
    echo "Toggle the advisory two with: /catalyst:hooks disable precompact|sessionstart"
    legacy_found=0
    for f in "$PROJECT_DIR"/.claude/hooks/*.sh; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in
        *handoff*) legacy_found=1 ;;
      esac
    done
    if [ "$legacy_found" -eq 1 ]; then
      echo
      echo "WARNING: legacy installed copies found in $PROJECT_DIR/.claude/hooks/."
      echo "  Those pre-date plugin-native delivery. They fire IN ADDITION to the"
      echo "  declarations above (duplicate output) and are frozen at the version"
      echo "  they were installed at. Remove them and any Catalyst entries in"
      echo "  .claude/settings.json."
    fi
    ;;
  enable)  k=$(key_for "${2:?usage: enable <precompact|sessionstart>}") && set_key "$k" true ;;
  disable) k=$(key_for "${2:?usage: disable <precompact|sessionstart>}") && set_key "$k" false ;;
  *)
    echo "usage: hooks-config.sh status | enable <precompact|sessionstart> | disable <precompact|sessionstart>" >&2
    exit 2 ;;
esac
