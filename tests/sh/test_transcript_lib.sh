#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/hooks/lib/transcript.sh"
FIX="$REPO_ROOT/tests/sh/fixtures"
fail=0

# Real nested shape: tool_use Read with file_path must be recovered.
got=$(sh_normalize_transcript "$FIX/real-transcript.jsonl" \
  | jq -rc 'select(.type=="tool_use" and .name=="Read") | .input.file_path')
[ "$got" = "/repo/src/a.ts" ] && echo "PASS real tool_use recovered" || { echo "FAIL real tool_use: got '$got'"; fail=1; }

# Real nested shape: tool_result content string must be recovered.
got=$(sh_normalize_transcript "$FIX/real-transcript.jsonl" \
  | jq -rc 'select(.type=="tool_result") | .content' | grep -c 'old_string not found')
[ "$got" -ge 1 ] && echo "PASS real tool_result content recovered" || { echo "FAIL real tool_result"; fail=1; }

# Flat legacy shape still passes through.
got=$(sh_normalize_transcript "$FIX/flat-transcript.jsonl" \
  | jq -rc 'select(.type=="tool_use" and .name=="Read") | .input.file_path')
[ "$got" = "/repo/src/a.ts" ] && echo "PASS flat passthrough" || { echo "FAIL flat: got '$got'"; fail=1; }

# Fail-open: malformed + missing file → empty, exit 0.
echo 'not json' > "$FIX/.tmp-bad.jsonl"
out=$(sh_normalize_transcript "$FIX/.tmp-bad.jsonl"; echo "rc=$?"); rm -f "$FIX/.tmp-bad.jsonl"
printf '%s' "$out" | grep -q 'rc=0' && echo "PASS fail-open malformed" || { echo "FAIL fail-open malformed: $out"; fail=1; }
out=$(sh_normalize_transcript "$FIX/does-not-exist.jsonl"; echo "rc=$?")
printf '%s' "$out" | grep -q 'rc=0' && echo "PASS fail-open missing" || { echo "FAIL fail-open missing"; fail=1; }

# Mixed good/bad line: bad line mid-stream must not truncate the tail.
_mixed_tmp=$(mktemp /tmp/test_transcript_XXXXXX.jsonl)
printf '%s\n' \
  '{"type":"assistant","timestamp":"2026-06-17T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/x.ts"}}]}}' \
  'not json' \
  '{"type":"assistant","timestamp":"2026-06-17T10:00:02Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/y.ts"}}]}}' \
  > "$_mixed_tmp"
_mixed_out=$(sh_normalize_transcript "$_mixed_tmp")
rm -f "$_mixed_tmp"
echo "$_mixed_out" | jq -e 'select(.type=="tool_use" and .input.file_path=="/repo/x.ts")' >/dev/null 2>&1 \
  && echo "PASS mixed good/bad: x.ts recovered" || { echo "FAIL mixed good/bad: x.ts not found"; fail=1; }
echo "$_mixed_out" | jq -e 'select(.type=="tool_use" and .input.file_path=="/repo/y.ts")' >/dev/null 2>&1 \
  && echo "PASS mixed good/bad: y.ts recovered" || { echo "FAIL mixed good/bad: y.ts not found (tail truncated)"; fail=1; }

# tool_result with ARRAY content: array must be joined into a string.
_arr_tmp=$(mktemp /tmp/test_transcript_XXXXXX.jsonl)
printf '%s\n' \
  '{"type":"user","timestamp":"2026-06-17T10:00:03Z","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"old_string not found"}]}]}}' \
  > "$_arr_tmp"
_arr_out=$(sh_normalize_transcript "$_arr_tmp")
rm -f "$_arr_tmp"
echo "$_arr_out" | jq -e 'select(.type=="tool_result") | .content | test("old_string not found")' >/dev/null 2>&1 \
  && echo "PASS tool_result array content joined" || { echo "FAIL tool_result array content: got $(echo "$_arr_out" | jq -r 'select(.type=="tool_result") | .content')"; fail=1; }

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
