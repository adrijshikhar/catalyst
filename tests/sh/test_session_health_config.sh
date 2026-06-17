#!/usr/bin/env bash
# Config precedence for session-health knobs: env > catalyst.json > default.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_ROOT/hooks/lib/session-health-signals.sh"
fail=0

run_eff() {  # args: project_dir ; echoes sh_effective_window in a clean subshell
  ( unset CATALYST_SH_ADVERTISED_TOKENS CATALYST_SH_EFFECTIVE_FRAC CATALYST_SH_PATTERN_WINDOW
    [ -n "${2:-}" ] && export "$2"
    CLAUDE_PROJECT_DIR="$1"; export CLAUDE_PROJECT_DIR
    . "$LIB"; sh_effective_window )
}

# 1) catalyst.json value flows in: advertised 1000000 × 0.70 = 700000
T1="$(mktemp -d)"; mkdir -p "$T1/.claude"
printf '%s' '{"session_health":{"advertised_tokens":1000000}}' > "$T1/.claude/catalyst.json"
got=$(run_eff "$T1" ""); [ "$got" = "700000" ] && echo "PASS json advertised -> $got" || { echo "FAIL json advertised: want 700000 got $got"; fail=1; }

# 2) env overrides json: env 500000 × 0.70 = 350000
got=$(run_eff "$T1" "CATALYST_SH_ADVERTISED_TOKENS=500000"); [ "$got" = "350000" ] && echo "PASS env overrides json -> $got" || { echo "FAIL env-over-json: want 350000 got $got"; fail=1; }

# 3) no file -> default 200000 × 0.70 = 140000
T2="$(mktemp -d)"; mkdir -p "$T2/.claude"
got=$(run_eff "$T2" ""); [ "$got" = "140000" ] && echo "PASS default no-file -> $got" || { echo "FAIL default: want 140000 got $got"; fail=1; }

# 4) malformed json -> fail-open to default 140000
printf '%s' '{ this is not json' > "$T2/.claude/catalyst.json"
got=$(run_eff "$T2" ""); [ "$got" = "140000" ] && echo "PASS malformed -> default $got" || { echo "FAIL malformed: want 140000 got $got"; fail=1; }

# 5) pattern_window from json
T3="$(mktemp -d)"; mkdir -p "$T3/.claude"
printf '%s' '{"session_health":{"pattern_window":42}}' > "$T3/.claude/catalyst.json"
gotw=$( unset CATALYST_SH_PATTERN_WINDOW; CLAUDE_PROJECT_DIR="$T3"; export CLAUDE_PROJECT_DIR; . "$LIB"; _sh_pattern_window )
[ "$gotw" = "42" ] && echo "PASS json pattern_window -> $gotw" || { echo "FAIL pattern_window: want 42 got $gotw"; fail=1; }

# 6) effective_frac from json: advertised 1000000 × 0.50 = 500000
T4="$(mktemp -d)"; mkdir -p "$T4/.claude"
printf '%s' '{"session_health":{"advertised_tokens":1000000,"effective_frac":0.50}}' > "$T4/.claude/catalyst.json"
got=$(run_eff "$T4" ""); [ "$got" = "500000" ] && echo "PASS json effective_frac -> $got" || { echo "FAIL json effective_frac: want 500000 got $got"; fail=1; }
rm -rf "${T4:?}"

rm -rf "${T1:?}" "${T2:?}" "${T3:?}"
[ "$fail" -eq 0 ] && echo "test_session_health_config: ALL PASS" || echo "test_session_health_config: FAILURES"
exit $fail
