#!/usr/bin/env bash
# handoff-dir.sh — print the centralized handoffs dir for the repo containing
# $1 (default: cwd). Mirrors scripts/handoff_paths.py:handoffs_dir().
# Worktree-aware: anchors at the main checkout (parent of the shared .git).
set -euo pipefail
DIR="${1:-$(pwd)}"
COMMON=$(git -C "$DIR" rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$COMMON" ]; then
  case "$COMMON" in /*) : ;; *) COMMON="$DIR/$COMMON" ;; esac
  COMMON=$(cd "$COMMON" 2>/dev/null && pwd || echo "$COMMON")
  if [ "$(basename "$COMMON")" = ".git" ]; then
    echo "$(dirname "$COMMON")/.claude/handoffs"
    exit 0
  fi
fi
echo "$DIR/.claude/handoffs"
