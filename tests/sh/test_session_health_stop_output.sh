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
cp "$REPO_ROOT/hooks/lib/transcript.sh" "$TMP/.claude/hooks/lib/"

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

# 3) edit-mismatch must FIRE on repeated "old_string not found" tool_results,
#    and must name BOTH distinct failing files (attribution regression).
EMT="$TMP/editmiss.jsonl"; : > "$EMT"
for f in a b; do
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/'"$f"'.ts"}}]}}' >> "$EMT"
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"Error: old_string not found in file"}]}}' >> "$EMT"
done
EVENT3=$(jq -n --arg t "$EMT" --arg c "$TMP" '{transcript_path:$t,session_id:"reg3",cwd:$c}')
out3=$(printf '%s' "$EVENT3" | CLAUDE_PROJECT_DIR="$TMP" bash "$TMP/.claude/hooks/Stop-session-health.sh" 2>/dev/null) || true
if printf '%s' "$out3" | grep -q 'edit-mismatch' \
   && printf '%s' "$out3" | grep -q 'src/a.ts' \
   && printf '%s' "$out3" | grep -q 'src/b.ts'; then
  echo "PASS edit-mismatch fires + names both failing files"
else
  echo "FAIL edit-mismatch attribution: $out3"; fail=1
fi

# 4) context-drowning detail must name the producing tool + KB, never ":<digits>".
BIG=$(head -c 18000 /dev/zero | tr '\0' 'x')
CDT="$TMP/drown.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"big.txt"}}]}}' > "$CDT"
printf '%s\n' "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"$BIG\"}]}}" >> "$CDT"
EVENT4=$(jq -n --arg t "$CDT" --arg c "$TMP" '{transcript_path:$t,session_id:"reg4",cwd:$c}')
out4=$(printf '%s' "$EVENT4" | CLAUDE_PROJECT_DIR="$TMP" bash "$TMP/.claude/hooks/Stop-session-health.sh" 2>/dev/null) || true
if printf '%s' "$out4" | grep -q 'context-drowning'; then
  d=$(printf '%s' "$out4" | grep -o 'Read result ~[0-9]*KB' | head -1 || true)
  if [ -n "$d" ] && ! printf '%s' "$out4" | grep -qE 'detail=":[0-9]+"'; then
    echo "PASS context-drowning names tool + KB ($d)"
  else
    echo "FAIL context-drowning detail wrong (empty tool / no KB): $out4"; fail=1
  fi
else
  echo "FAIL context-drowning did not fire: $out4"; fail=1
fi

# 5) Stop summary must say "recent activity (last N tool calls)" not "this session"
if printf '%s' "$out" | grep -q 'recent activity (last [0-9]* tool calls)'; then
  echo "PASS Stop summary says 'recent activity (last N tool calls)'"
else
  echo "FAIL Stop summary still says 'this session': $out"; fail=1
fi

# 6) edit-mismatch empty-file-list guard: when NO preceding Edit exists in-window,
#    file list is empty → fallback to "recently edited file(s)" instead of trailing space.
EFT="$TMP/editfail_nopreced.jsonl"; : > "$EFT"
# Two tool_results with "old_string not found", but NO preceding Edit tool_use
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"Error: old_string not found in file"}]}}' >> "$EFT"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"Error: old_string not found in file"}]}}' >> "$EFT"
EVENT5=$(jq -n --arg t "$EFT" --arg c "$TMP" '{transcript_path:$t,session_id:"reg5",cwd:$c}')
out5=$(printf '%s' "$EVENT5" | CLAUDE_PROJECT_DIR="$TMP" bash "$TMP/.claude/hooks/Stop-session-health.sh" 2>/dev/null) || true
if printf '%s' "$out5" | grep -q 'edit-mismatch' \
   && printf '%s' "$out5" | grep -q 'recently edited file(s)' \
   && ! printf '%s' "$out5" | grep -qE 'failed Edits on *"' \
   && ! printf '%s' "$out5" | grep -qE 'failed Edits on  ' ; then
  echo "PASS edit-mismatch empty-file-list fallback works (no double-space, no trailing on)"
else
  echo "FAIL edit-mismatch empty-file-list guard: $out5"; fail=1
fi

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
