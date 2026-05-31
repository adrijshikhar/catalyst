#!/usr/bin/env bash
# Regression: Stop-session-health.sh must emit a VALID Stop-hook payload on a
# real detection — `systemMessage`, never `hookSpecificOutput.additionalContext`
# (which Claude Code rejects for Stop). Also: instruction-fade must NOT fire on
# a transcript of empty/null user turns (the "null" false-positive).
# The existing hook smoke only feeds EMPTY transcripts, so it never exercised
# the detection output path where both bugs lived.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/Stop-session-health.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
fail=0

mkdir -p "$TMP/.claude/hooks/lib"
cp "$HOOK" "$TMP/.claude/hooks/"
cp "$REPO_ROOT/hooks/lib/session-health-signals.sh" "$TMP/.claude/hooks/lib/"

# 1) Detection path: a transcript with the same Bash command repeated → fires
#    repeated-tool-call. Output must be valid Stop schema.
TRANSCRIPT="$TMP/repeat.jsonl"
for _ in 1 2 3 4; do
  printf '%s\n' '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}' >> "$TRANSCRIPT"
done
EVENT=$(jq -n --arg t "$TRANSCRIPT" --arg c "$TMP" '{transcript_path:$t,session_id:"reg",cwd:$c}')
out=$(printf '%s' "$EVENT" | CLAUDE_PROJECT_DIR="$TMP" bash "$TMP/.claude/hooks/Stop-session-health.sh" 2>/dev/null) || { echo "FAIL: hook non-zero exit"; fail=1; }

if [ -n "$out" ]; then
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    echo "FAIL: detection output is not valid JSON: $out"; fail=1
  fi
  # MUST use systemMessage, MUST NOT use hookSpecificOutput (invalid for Stop)
  if printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1; then
    echo "PASS: Stop emits systemMessage on detection"
  else
    echo "FAIL: Stop detection output lacks .systemMessage: $out"; fail=1
  fi
  if printf '%s' "$out" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; then
    echo "FAIL: Stop emits hookSpecificOutput (invalid Stop schema): $out"; fail=1
  else
    echo "PASS: Stop does not emit hookSpecificOutput"
  fi
else
  echo "FAIL: detection path produced no output (expected a systemMessage)"; fail=1
fi

# 2) instruction-fade false-positive guard: a transcript of empty/null user
#    turns must NOT surface an "instruction-fade: null" detection.
NULLT="$TMP/nulls.jsonl"
for _ in 1 2 3 4; do
  printf '%s\n' '{"type":"user","content":null}' >> "$NULLT"
done
EVENT2=$(jq -n --arg t "$NULLT" --arg c "$TMP" '{transcript_path:$t,session_id:"reg2",cwd:$c}')
out2=$(printf '%s' "$EVENT2" | CLAUDE_PROJECT_DIR="$TMP" bash "$TMP/.claude/hooks/Stop-session-health.sh" 2>/dev/null) || true
if printf '%s' "$out2" | grep -q 'instruction-fade'; then
  echo "FAIL: instruction-fade fired on null/empty user turns: $out2"; fail=1
else
  echo "PASS: no instruction-fade false-positive on null user turns"
fi

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
