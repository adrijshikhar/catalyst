#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/hooks/lib/session-health-signals.sh"
FIX="$REPO_ROOT/tests/sh/fixtures"; fail=0
# Exact: last assistant usage context = input+cache_read+cache_creation = 100+1000+0
n=$(sh_count_tokens "$FIX/usage-transcript.jsonl")
[ "$n" = "1100" ] && echo "PASS token count = last-assistant usage (1100)" || { echo "FAIL token: got '$n' want 1100"; fail=1; }
# No usage → suppress (0)
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}' > "$FIX/.tmp-nousage.jsonl"
n=$(sh_count_tokens "$FIX/.tmp-nousage.jsonl"); rm -f "$FIX/.tmp-nousage.jsonl"
[ "$n" = "0" ] && echo "PASS no-usage → 0 (suppress)" || { echo "FAIL no-usage: got '$n' want 0"; fail=1; }
[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
