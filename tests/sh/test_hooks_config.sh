#!/usr/bin/env bash
# tests/sh/test_hooks_config.sh — the shared enabled-check and the two
# lifecycle knobs. Boolean parsing lives ONLY in catalyst_config_enabled;
# a hook that re-implements the falsy check is the duplication this guards.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT
fail=0

# shellcheck source=/dev/null
. "$REPO_ROOT/hooks/lib/config.sh"

mkdir -p "$TMP/.claude"
cfg() { printf '%s' "$1" > "$TMP/.claude/catalyst.json"; }

check() { # label expected-rc actual-rc
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected rc=$2, got rc=$3"; fail=1; fi
}

enabled_rc() { # key -> prints rc without aborting under set -e
  local rc=0
  CLAUDE_PROJECT_DIR="$TMP" catalyst_config_enabled "$1" || rc=$?
  printf '%s' "$rc"
}

# T1: absent key -> enabled
cfg '{}'
check "T1 absent key enabled" 0 "$(enabled_rc hooks.precompact_prompt)"

# T2-T5: every documented falsy spelling -> disabled
for v in 'false' '0' '"no"' '"OFF"'; do
  cfg "{\"hooks\":{\"precompact_prompt\":$v}}"
  check "T2 falsy $v disabled" 1 "$(enabled_rc hooks.precompact_prompt)"
done

# T6: a non-falsy value -> enabled
cfg '{"hooks":{"precompact_prompt":true}}'
check "T6 true enabled" 0 "$(enabled_rc hooks.precompact_prompt)"

# T7: malformed config -> enabled (fail toward the plugin working)
printf '%s' '{not json' > "$TMP/.claude/catalyst.json"
check "T7 malformed config enabled" 0 "$(enabled_rc hooks.precompact_prompt)"

# T8: env override reaches the helper
cfg '{}'
rc=0; CATALYST_HOOKS_PRECOMPACT_PROMPT=false CLAUDE_PROJECT_DIR="$TMP" \
  catalyst_config_enabled hooks.precompact_prompt || rc=$?
check "T8 env override disables" 1 "$rc"

# T9: the two knobs are independent
cfg '{"hooks":{"precompact_prompt":false}}'
check "T9a precompact disabled" 1 "$(enabled_rc hooks.precompact_prompt)"
check "T9b sessionstart still enabled" 0 "$(enabled_rc hooks.sessionstart_resume)"

# --- hook-level: a falsy knob makes the hook exit 0 with NO output ---
# Empty output matters as much as the exit code: these hooks inject context,
# so a disabled hook that still prints has not been disabled.
H="$REPO_ROOT/hooks"

cfg '{"hooks":{"precompact_prompt":false}}'
out=$(CLAUDE_PROJECT_DIR="$TMP" bash "$H/PreCompact-handoff-write.sh" 2>&1) || true
if [ -z "$out" ]; then echo "PASS T10 PreCompact silent when disabled"
else echo "FAIL T10: expected empty output, got: $out"; fail=1; fi

# T11: SessionStart's disabled path only proves something if the ENABLED path
# would otherwise speak. $TMP has no git repo and no brief on disk, so the
# hook's own "no brief" early-exit already yields empty output regardless of
# the guard — that made T11 vacuous (PASS even with the guard deleted). Give
# it a real project with a brief (same shape as the S5 fixture below: git
# init, a branch, a <store>/<branch>.json) so silence is actual evidence.
T11_DIR="$(mktemp -d)"
git -C "$T11_DIR" init -q
git -C "$T11_DIR" checkout -q -b main 2>/dev/null || true
mkdir -p "$T11_DIR/.claude/handoffs"
cat > "$T11_DIR/.claude/handoffs/main.json" <<'BRIEF'
{"schema_version":"1","key":"main","timestamp":"2026-09-03T00:00:00Z","mode":"WRITE",
 "resume":{"done_when":"d","resume_by":"r"},
 "state":{"branch":"main","next_acceptance_check":"c",
          "worktree":{"root":"/w","is_linked":false,"git_common_dir":"/w/.git"}}}
BRIEF
cfg_t11() { printf '%s' "$1" > "$T11_DIR/.claude/catalyst.json"; }

cfg_t11 '{}'
out=$(printf '%s' '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$T11_DIR" bash "$H/SessionStart-handoff-read.sh" 2>&1) || true
if printf '%s' "$out" | grep -q 'hookSpecificOutput'; then
  echo "PASS T11a SessionStart speaks when enabled (proves the fixture is live)"
else
  echo "FAIL T11a: expected hookSpecificOutput from the enabled hook with a real brief, got: $out"; fail=1
fi

cfg_t11 '{"hooks":{"sessionstart_resume":false}}'
out=$(printf '%s' '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$T11_DIR" bash "$H/SessionStart-handoff-read.sh" 2>&1) || true
if [ -z "$out" ]; then echo "PASS T11b SessionStart silent when disabled (same brief, same project)"
else echo "FAIL T11b: expected empty output, got: $out"; fail=1; fi
rm -rf "${T11_DIR:?}"

# T12: disabling one must not disable the other. PreCompact still speaks.
cfg '{"hooks":{"sessionstart_resume":false}}'
out=$(CLAUDE_PROJECT_DIR="$TMP" bash "$H/PreCompact-handoff-write.sh" 2>&1) || true
if printf '%s' "$out" | grep -q 'systemMessage'; then echo "PASS T12 knobs are independent"
else echo "FAIL T12: PreCompact went silent under the wrong knob: $out"; fail=1; fi

# T13: no hook re-implements the falsy check — it belongs to the helper alone.
if grep -qE 'false\|0\|no\|off' "$H"/*.sh; then
  echo "FAIL T13: a hook spells out its own falsy check; use catalyst_config_enabled"; fail=1
else
  echo "PASS T13 falsy parsing lives only in the shared helper"
fi

# --- scripts/hooks-config.sh: status / enable / disable ---
HC="$REPO_ROOT/scripts/hooks-config.sh"
P2="$(mktemp -d)"

# T14: status works with no config at all and reports both enabled
out=$(CLAUDE_PROJECT_DIR="$P2" bash "$HC" status 2>&1) || true
if printf '%s' "$out" | grep -q 'PreCompact' && printf '%s' "$out" | grep -qi 'enabled'; then
  echo "PASS T14 status with no config reports enabled"
else
  echo "FAIL T14: got: $out"; fail=1
fi

# T15/T16: disable then enable round-trips through the config file
CLAUDE_PROJECT_DIR="$P2" bash "$HC" disable precompact >/dev/null 2>&1
v=$(CLAUDE_PROJECT_DIR="$P2" bash "$REPO_ROOT/scripts/catalyst-config.sh" get hooks.precompact_prompt true)
check "T15 disable writes false" "false" "$v"
CLAUDE_PROJECT_DIR="$P2" bash "$HC" enable precompact >/dev/null 2>&1
v=$(CLAUDE_PROJECT_DIR="$P2" bash "$REPO_ROOT/scripts/catalyst-config.sh" get hooks.precompact_prompt false)
check "T16 enable writes true" "true" "$v"

# T17: the config file stays valid JSON and other keys survive
printf '%s' '{"handoff":{"stale_hours":30}}' > "$P2/.claude/catalyst.json"
CLAUDE_PROJECT_DIR="$P2" bash "$HC" disable sessionstart >/dev/null 2>&1
if jq -e '.handoff.stale_hours == 30 and .hooks.sessionstart_resume == false' \
     "$P2/.claude/catalyst.json" >/dev/null 2>&1; then
  echo "PASS T17 unrelated config keys preserved"
else
  echo "FAIL T17: clobbered other keys: $(cat "$P2/.claude/catalyst.json")"; fail=1
fi

# T19: status warns about legacy installed copies, which double-fire and freeze
mkdir -p "$P2/.claude/hooks"
cp "$REPO_ROOT/hooks/PreCompact-handoff-write.sh" "$P2/.claude/hooks/"
out=$(CLAUDE_PROJECT_DIR="$P2" bash "$HC" status 2>&1) || true
if printf '%s' "$out" | grep -qi 'legacy'; then
  echo "PASS T19 status warns about legacy copies"
else
  echo "FAIL T19: no legacy warning: $out"; fail=1
fi
rm -rf "${P2:?}"

# T20: a write that fails must not report success, must not leave a stray
# temp file, and must not touch the original (malformed) config.
P3="$(mktemp -d)"
mkdir -p "$P3/.claude"
printf '%s' '{not json' > "$P3/.claude/catalyst.json"
rc=0
out=$(CLAUDE_PROJECT_DIR="$P3" bash "$HC" disable precompact 2>&1) || rc=$?
if [ "$rc" -ne 0 ] \
   && ! printf '%s' "$out" | grep -q 'Set hooks.precompact_prompt' \
   && [ ! -e "$P3/.claude/catalyst.json.tmp" ] \
   && [ "$(cat "$P3/.claude/catalyst.json")" = '{not json' ]; then
  echo "PASS T20 failed write reports failure, leaves no tmp file, config untouched"
else
  echo "FAIL T20: rc=$rc out=$out tmp=$([ -e "$P3/.claude/catalyst.json.tmp" ] && echo present || echo absent) cfg=$(cat "$P3/.claude/catalyst.json")"
  fail=1
fi
rm -rf "${P3:?}"

[ "$fail" -eq 0 ] && echo "test_hooks_config: ALL PASS" || echo "test_hooks_config: FAILURES"
exit $fail
