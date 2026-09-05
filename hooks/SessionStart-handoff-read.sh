#!/usr/bin/env bash
# SessionStart-handoff-read.sh — Catalyst hooks
#
# Fires on session start. Detects whether a relevant handoff brief exists
# for the current branch. If so, injects a prompt to invoke handoff READ.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Fail-open on missing jq. Must precede every jq use, including the degraded
# message below.
if ! command -v jq >/dev/null 2>&1; then exit 1; fi


# SessionStart stdin carries the source: startup | resume | clear | compact | fork.
# Read it once; default to startup so a missing/garbled payload is harmless.
INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo startup)"
[ -n "$SOURCE" ] || SOURCE="startup"

# Project dir: Claude Code sets CLAUDE_PROJECT_DIR; Codex and Antigravity do not,
# but every host puts `cwd` in the hook payload. Fall back to it, then to pwd, so
# a brief written under one agent is found when another agent opens the repo.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)}"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"

# Degraded-library branch.
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/config.sh" 2>/dev/null || true
if ! command -v catalyst_store_dir >/dev/null 2>&1; then
  jq -n '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: "Catalyst SessionStart hook is degraded: hooks/lib/config.sh was not found beside this hook, which means the plugin cache is incomplete. Reinstall the plugin. No handoff brief was checked for this session."}}'
  exit 0
fi

# Opt out: `hooks.sessionstart_resume: false` in .claude/catalyst.json, or
# CATALYST_HOOKS_SESSIONSTART_RESUME=false.
if ! catalyst_config_enabled hooks.sessionstart_resume; then
  exit 0
fi

BRANCH=""
# Worktree-safe repo detection: in a linked worktree `.git` is a FILE, so
# `[ -d .git ]` is false and branch detection would be skipped, wrongly
# surfacing the legacy slot instead of the branch-keyed brief. Use git itself.
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
fi

STORE=$(catalyst_store_dir "$PROJECT_DIR")
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
