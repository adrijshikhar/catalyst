#!/usr/bin/env bash
# tests/sh/test_catalyst_config.sh — bash reader: precedence + fail-open.
# Python-side coverage and bash/python parity live in
# tests/test_catalyst_config.py; this file guards the sourced-lib path that
# installed hooks actually take.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$REPO_ROOT/scripts/catalyst-config.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0

check() { # label expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}

mkdir -p "$TMP/.claude"

# T1: default when nothing is configured
check "T1 default" "24" \
  "$(CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" get handoff.stale_hours 24)"

# T2: json beats default
printf '%s' '{"handoff":{"stale_hours":1}}' > "$TMP/.claude/catalyst.json"
check "T2 json beats default" "1" \
  "$(CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" get handoff.stale_hours 24)"

# T3: env beats json
check "T3 env beats json" "7" \
  "$(CATALYST_HANDOFF_STALE_HOURS=7 CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" get handoff.stale_hours 24)"

# T4: malformed json fails open to the default (must not abort the hook)
printf '%s' '{not json' > "$TMP/.claude/catalyst.json"
check "T4 malformed json fails open" "24" \
  "$(CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" get handoff.stale_hours 24)"

# T5: structured value is NOT returned by the scalar reader
printf '%s' '{"example":{"items":[{"writes_to":"x.json"}]}}' > "$TMP/.claude/catalyst.json"
check "T5 scalar reader refuses a structure" "FALLBACK" \
  "$(CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" get example.items FALLBACK)"

# T6: structured value IS returned by the json reader
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CLI" json example.items)"
if printf '%s' "$out" | grep -q '"writes_to":"x.json"'; then
  echo "PASS T6 json reader returns the array"
else
  echo "FAIL T6: expected the claims array, got '$out'"; fail=1
fi

# T7: store dir resolves to the main worktree from a linked worktree
# Resolve to the physical path (macOS TMPDIR is under /var, a symlink to
# /private/var) — matches the pwd -P idiom tests/sh/test_hook_smoke.sh
# already uses for this identical scenario, so the comparison is stable
# regardless of whether the host's tmpdir involves a symlink.
REPO="$TMP/repo"; mkdir -p "$REPO"
REPO="$(cd "$REPO" && pwd -P)"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t
echo x > "$REPO/f.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
git -C "$REPO" worktree add -q "$TMP/wt" -b feat
check "T7 linked worktree centralizes" "$REPO/.claude/handoffs" \
  "$(bash "$CLI" store "$TMP/wt")"

[ "$fail" -eq 0 ] && echo "test_catalyst_config: ALL PASS" || echo "test_catalyst_config: FAILURES"
exit $fail
