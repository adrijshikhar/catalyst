#!/usr/bin/env bash
# Regression: install-hooks.sh must NOT nest lib/ on re-install.
# `cp -r src/lib dest/lib` copies INTO dest/lib when it already exists →
# dest/lib/lib (observed in catalyst + fortress .claude/hooks/). A second
# install of a lib-using hook must leave the libs at lib/<file>, no lib/lib.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0
S="$REPO_ROOT/scripts/install-hooks.sh"

# Install a session-health hook (which carries lib/) TWICE into a fresh project.
CLAUDE_PROJECT_DIR="$TMP" bash "$S" install Stop Stop-session-health.sh >/dev/null 2>&1 || { echo "FAIL: first install non-zero"; fail=1; }
CLAUDE_PROJECT_DIR="$TMP" bash "$S" install Stop Stop-session-health.sh >/dev/null 2>&1 || { echo "FAIL: second install non-zero"; fail=1; }

if [ -e "$TMP/.claude/hooks/lib/lib" ]; then
  echo "FAIL: nested lib/lib created on re-install"; fail=1
else
  echo "PASS: no nested lib/lib after re-install"
fi
if [ -f "$TMP/.claude/hooks/lib/session-health-signals.sh" ]; then
  echo "PASS: lib/session-health-signals.sh present at correct level"
else
  echo "FAIL: lib/session-health-signals.sh missing"; fail=1
fi

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
