#!/usr/bin/env bash
# Stop pattern matchers must scope to the last N tool events, not the whole
# transcript. Old activity beyond the window must NOT trip a pattern.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO_ROOT/hooks/lib/transcript.sh"
. "$REPO_ROOT/hooks/lib/session-health-signals.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0

# Helper returns at most N events.
T="$TMP/many.jsonl"; : > "$T"
for i in $(seq 1 150); do
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo '"$i"'"}}]}}' >> "$T"
done
n=$(sh_recent_tool_events "$T" 100 | wc -l | tr -d ' ')
[ "$n" = "100" ] && echo "PASS helper returns last 100" || { echo "FAIL helper window: got $n"; fail=1; }

# Scoping: 3 stale-read-style/recovery events OLD (pushed out of window) then 120 clean Bash → recovery-spiral must NOT fire.
T2="$TMP/old.jsonl"; : > "$T2"
for f in a b c a b c a b c; do printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"'"$f"'.ts"}}]}}' >> "$T2"; done
for i in $(seq 1 120); do printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo '"$i"'"}}]}}' >> "$T2"; done
out=$(CATALYST_SH_PATTERN_WINDOW=100 bash -c '. '"$REPO_ROOT"'/hooks/lib/transcript.sh; . '"$REPO_ROOT"'/hooks/lib/session-health-signals.sh; sh_pattern_recovery_spiral "'"$T2"'" 3 || true')
[ -z "$out" ] && echo "PASS recovery-spiral scoped out (old activity)" || { echo "FAIL recovery-spiral fired on out-of-window activity: $out"; fail=1; }

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
