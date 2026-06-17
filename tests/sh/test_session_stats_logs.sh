#!/usr/bin/env bash
# session-stats.sh must surface alerts from the LIVE log (.claude/session-health.log),
# not the retired session-degradation.log / failure-patterns.log paths.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0
mkdir -p "$TMP/.claude"
printf '%s\n' '2026-06-17T10:00:00Z session=abc pattern=repeated-tool-call recipe=try-different-approach' \
  > "$TMP/.claude/session-health.log"
out=$(CLAUDE_PROJECT_DIR="$TMP" bash "$REPO_ROOT/scripts/session-stats.sh" "" 2>/dev/null) || { echo "FAIL: non-zero exit"; fail=1; }
if printf '%s' "$out" | grep -q 'repeated-tool-call'; then
  echo "PASS: session-stats surfaces a session-health.log alert"
else
  echo "FAIL: alert from session-health.log not in report: $out"; fail=1
fi
[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
