#!/usr/bin/env bash
# Functional smoke for every hook: install into a throwaway temp git repo,
# pipe a minimal event, assert it exits 0 and (when it emits) emits valid JSON.
# Temp-git-repo isolation prevents Stop-commit-backstop touching the real tree.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

cd "$TMP"
git init -q && git config user.email t@e.st && git config user.name test
echo init > f.txt && git add f.txt && git commit -qm init
mkdir -p .claude/hooks
cp "$REPO_ROOT"/hooks/*.sh .claude/hooks/ 2>/dev/null || true
chmod +x .claude/hooks/*.sh

EVENT='{"transcript_path":"","session_id":"smoke","cwd":"'"$TMP"'"}'
for hook in .claude/hooks/*.sh; do
  name="$(basename "$hook")"
  out=$(printf '%s' "$EVENT" | CLAUDE_PROJECT_DIR="$TMP" bash "$hook" 2>/dev/null) || {
    echo "FAIL $name: non-zero exit"; fail=1; continue; }
  if [ -n "$out" ]; then
    if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      echo "PASS $name (valid JSON)"
    else
      echo "FAIL $name: emitted non-JSON: $out"; fail=1
    fi
  else
    echo "PASS $name (no output, exit 0)"
  fi
done

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
