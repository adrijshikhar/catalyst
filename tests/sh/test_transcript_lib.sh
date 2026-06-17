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

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
