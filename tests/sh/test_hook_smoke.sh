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

# Regression: PreCompact must NOT crash on $KEY-unbound in a NON-git dir
# (no branch → legacy slot). Catches the set -u unbound-variable bug.
NOGIT="$(mktemp -d)"
mkdir -p "$NOGIT/.claude/hooks"
cp "$REPO_ROOT/hooks/PreCompact-handoff-write.sh" "$NOGIT/.claude/hooks/"
out=$(printf '%s' '{"transcript_path":"","session_id":"smoke"}' | CLAUDE_PROJECT_DIR="$NOGIT" bash "$NOGIT/.claude/hooks/PreCompact-handoff-write.sh" 2>/dev/null) || { echo "FAIL PreCompact (no-git): non-zero exit"; fail=1; }
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("legacy")' >/dev/null 2>&1; then
  echo "PASS PreCompact no-branch (legacy slot, no crash)"
else
  echo "FAIL PreCompact no-branch: expected legacy-slot JSON, got: $out"; fail=1
fi
rm -rf "$NOGIT"

# Regression: the verify-gate fractional-second timestamp normalization must
# yield a parseable timestamp on THIS host (macOS BSD date or GNU date).
# Mirrors the hook's normalization + parse; guards the macOS fail-open bug (#2).
READ_TS="2024-01-01T00:00:00.123Z"
case "$READ_TS" in *.*) READ_TS="${READ_TS%.*}Z" ;; esac
if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s" >/dev/null 2>&1 \
   || date -u -d "$READ_TS" "+%s" >/dev/null 2>&1; then
  echo "PASS verify-gate fractional-timestamp normalizes + parses ($READ_TS)"
else
  echo "FAIL verify-gate: normalized timestamp '$READ_TS' still unparseable on this host"; fail=1
fi

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
