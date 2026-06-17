#!/usr/bin/env bash
# SessionStart-handoff-read.sh — Catalyst hooks
#
# Fires on session start. Detects whether a relevant handoff brief exists
# for the current branch. If so, injects a prompt to invoke handoff READ.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# SessionStart stdin carries the source: startup | resume | clear | compact.
# Read it once; default to startup so a missing/garbled payload is harmless.
INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo startup)"
[ -n "$SOURCE" ] || SOURCE="startup"

# Resolve the centralized handoffs store — anchored at the MAIN worktree
# (parent of the shared .git). Inlined (not calling scripts/handoff-dir.sh)
# because installed hooks ship standalone in .claude/hooks/ without scripts/.
# Mirrors scripts/handoff-dir.sh + handoff_paths.py (parity test guards those).
resolve_store() {
  local dir="$1" common
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || true)
  if [ -n "$common" ]; then
    case "$common" in /*) : ;; *) common="$dir/$common" ;; esac
    common=$(cd "$common" 2>/dev/null && pwd || echo "$common")
    if [ "$(basename "$common")" = ".git" ]; then
      echo "$(dirname "$common")/.claude/handoffs"
      return
    fi
  fi
  echo "$dir/.claude/handoffs"
}

BRANCH=""
# Worktree-safe repo detection: in a linked worktree `.git` is a FILE, so
# `[ -d .git ]` is false and branch detection would be skipped, wrongly
# surfacing the legacy slot instead of the branch-keyed brief. Use git itself.
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

STORE=$(resolve_store "$PROJECT_DIR")
LEGACY_PATH="$STORE/HANDOFF.json"
KEYED_PATH=""
if [ -n "$BRANCH" ]; then
  KEY=$(echo "$BRANCH" | sed 's|/|-|g' | cut -c1-80)
  KEYED_PATH="$STORE/$KEY.json"
fi

EXISTS_KEYED="no"
EXISTS_LEGACY="no"
[ -f "$KEYED_PATH" ] && [ -n "$KEYED_PATH" ] && EXISTS_KEYED="yes"
[ -f "$LEGACY_PATH" ] && EXISTS_LEGACY="yes"

if [ "$EXISTS_KEYED" = "no" ] && [ "$EXISTS_LEGACY" = "no" ]; then
  exit 0  # No brief, no message
fi

# Pick the brief to act on — branch-keyed wins over legacy.
BRIEF_PATH=""
BRIEF_KIND=""
if [ "$EXISTS_KEYED" = "yes" ]; then
  BRIEF_PATH="$KEYED_PATH"; BRIEF_KIND="branch"
elif [ "$EXISTS_LEGACY" = "yes" ]; then
  BRIEF_PATH="$LEGACY_PATH"; BRIEF_KIND="legacy"
fi

# On clear/compact the session was just reset or condensed and a brief is on
# disk — the user always wants it back. Render the five load-bearing fields
# directly (auto-resume) so no third `/handoff resume` is needed. Other sources
# keep the light announce so ordinary new sessions aren't force-fed ~1-2KB.
# Fail-open: any jq error leaves RENDERED empty and we fall back to announce.
RENDERED=""
case "$SOURCE" in
  clear|compact)
    RENDERED=$(jq -r --arg src "$SOURCE" '
      "# Resumed (auto, on /\($src)) — \(.key // "—")\n\n"
      + "## Next step\n\(.resume.resume_by // "—")\n\n"
      + "## Done when\n\(.resume.done_when // "—")\n\n"
      + "## Next acceptance check\n\(.state.next_acceptance_check // "—")\n\n"
      + "## Open risks\n"
        + (if ((.state.open_risks // []) | length) == 0 then "—"
           else ((.state.open_risks) | map("- \(.)") | join("\n")) end)
        + "\n\n"
      + "## Read first\n"
        + (if ((.files_read_first // []) | length) == 0 then "—"
           else ((.files_read_first) | map("- \(.path) — \(.why)") | join("\n")) end)
    ' "$BRIEF_PATH" 2>/dev/null) || RENDERED=""
    ;;
esac

if [ -n "$RENDERED" ]; then
  CTX="$RENDERED"
elif [ "$BRIEF_KIND" = "branch" ]; then
  CTX="A handoff brief exists for the current branch at $KEYED_PATH. Invoke the handoff skill in READ mode (renders via scripts/handoff-render.py) if the user wants to resume."
else
  CTX="A legacy handoff brief exists at $LEGACY_PATH. Invoke the handoff skill in READ mode (renders via scripts/handoff-render.py — legacy / tier-3 fallback) if the user wants to resume."
fi

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
