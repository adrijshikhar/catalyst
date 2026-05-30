#!/usr/bin/env bash
# scripts/install-hooks.sh — shared logic for installing Catalyst hooks
#
# Usage:
#   bash scripts/install-hooks.sh install <event> <hook-filename> <matcher>
#   bash scripts/install-hooks.sh uninstall <event> <hook-filename>
#
# Where:
#   <event>          = PreToolUse | PostToolUse | PreCompact | SessionStart | Stop | UserPromptSubmit
#   <hook-filename>  = e.g., PreToolUse-verify-gate.sh
#   <matcher>        = optional regex for tool name (only PreToolUse/PostToolUse)

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HOOKS_SRC_DIR="${HOOKS_SRC_DIR:-$(cd "$(dirname "$0")/.." && pwd)/hooks}"
HOOKS_DEST_DIR="$PROJECT_DIR/.claude/hooks"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install jq (brew install jq / apt-get install jq) and retry." >&2
  exit 1
fi

ACTION="${1:-}"
EVENT="${2:-}"
HOOK_FILE="${3:-}"
MATCHER="${4:-}"

if [ -z "$ACTION" ] || [ -z "$EVENT" ] || [ -z "$HOOK_FILE" ]; then
  echo "Usage: install-hooks.sh <install|uninstall> <event> <hook-filename> [matcher]" >&2
  exit 2
fi

mkdir -p "$HOOKS_DEST_DIR"
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{"hooks":{}}' > "$SETTINGS_FILE"
fi

case "$ACTION" in
  install)
    if [ ! -f "$HOOKS_SRC_DIR/$HOOK_FILE" ]; then
      echo "ERROR: hook source not found at $HOOKS_SRC_DIR/$HOOK_FILE" >&2
      exit 3
    fi
    cp "$HOOKS_SRC_DIR/$HOOK_FILE" "$HOOKS_DEST_DIR/$HOOK_FILE"
    chmod +x "$HOOKS_DEST_DIR/$HOOK_FILE"
    # Copy the shared signal library if it exists (used by session-health hooks).
    if [ -d "$HOOKS_SRC_DIR/lib" ]; then
      cp -r "$HOOKS_SRC_DIR/lib" "$HOOKS_DEST_DIR/lib"
    fi

    CMD="bash \$CLAUDE_PROJECT_DIR/.claude/hooks/$HOOK_FILE"
    # Claude Code settings.json hook schema:
    #   .hooks.<Event> = [{matcher, hooks: [{type: "command", command}]}]
    # Matcher is "" for non-tool events (PreCompact, SessionStart, Stop,
    # UserPromptSubmit) and a tool-name regex for PreToolUse/PostToolUse.
    NEW_ENTRY=$(jq -n --arg cmd "$CMD" --arg matcher "$MATCHER" \
      '{matcher: $matcher, hooks: [{type: "command", command: $cmd}]}')

    # Idempotency: if any matcher-group for this event already contains a
    # hook with the same command, skip.
    EXISTS=$(jq --arg cmd "$CMD" --arg event "$EVENT" \
      '[(.hooks[$event] // [])[] | (.hooks // [])[] | select(.command == $cmd)] | length' \
      "$SETTINGS_FILE")
    if [ "$EXISTS" -gt 0 ]; then
      echo "Hook already installed for $EVENT — no change."
      exit 0
    fi

    jq --argjson entry "$NEW_ENTRY" --arg event "$EVENT" '
      .hooks //= {} |
      .hooks[$event] //= [] |
      .hooks[$event] += [$entry]
    ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

    echo "Installed: $EVENT -> $HOOK_FILE"
    ;;

  uninstall)
    if [ -f "$HOOKS_DEST_DIR/$HOOK_FILE" ]; then
      rm "$HOOKS_DEST_DIR/$HOOK_FILE"
    fi
    CMD="bash \$CLAUDE_PROJECT_DIR/.claude/hooks/$HOOK_FILE"
    # Remove matching command from every matcher-group's inner hooks array,
    # then drop matcher-groups that became empty.
    jq --arg cmd "$CMD" --arg event "$EVENT" '
      .hooks[$event] //= [] |
      .hooks[$event] |= (
        map(.hooks |= map(select(.command != $cmd)))
        | map(select((.hooks // []) | length > 0))
      )
    ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

    echo "Uninstalled: $EVENT -> $HOOK_FILE"
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    exit 2
    ;;
esac
