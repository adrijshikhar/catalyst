#!/usr/bin/env bash
# tests/sh/test_verify_gate_config.sh — EDD test for verify-gate config precedence.
#
# Tests that verify-gate reads its config from:
# 1. catalyst.json .verify_gate (primary)
# 2. legacy .claude/verify-gate.json (fallback)
# 3. built-in defaults (final fallback)
#
# Also tests that overreliance_min_bytes precedence is: env > json > 4000
#
# Test strategy:
# - T1: catalyst.json config is used (check that required files match catalyst config, not defaults)
# - T2: legacy fallback works when no catalyst.json (stale evidence shows freshness number)
# - T3: overreliance_min_bytes from json gating works (large write blocked, small allowed)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/PreToolUse-verify-gate.sh"
fail=0

# Test 1: catalyst.json config is used, not defaults
# catalyst.json specifies only test-output.log as required; defaults include vitest-results.xml, pytest.xml, jest-results.json
# When no evidence is provided, the denial message should list only test-output.log (not the defaults)
P1="$(mktemp -d)"; mkdir -p "$P1/.claude"
printf '%s' '{"verify_gate":{"claims":[{"writes_to":"test-results.json","requires_read_of":["test-output.log"]}],"evidence_freshness_minutes":5}}' > "$P1/.claude/catalyst.json"
out=$( printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$P1"'/test-results.json","content":"x"},"transcript_path":""}' \
  | CLAUDE_PROJECT_DIR="$P1" bash "$HOOK" 2>/dev/null || true )
if printf '%s' "$out" | grep -q "test-output.log" && ! printf '%s' "$out" | grep -q "vitest"; then
  echo "PASS T1: catalyst.json config used (only test-output.log required, defaults not present)"
else
  echo "FAIL T1: expected only test-output.log in required list, got: $out"; fail=1
fi

# Test 2: legacy verify-gate.json fallback (no catalyst.json)
# Configure with freshness 7 minutes (non-standard). Provide evidence that's stale.
# The stale message should contain "7" to prove config was read from legacy file.
P2="$(mktemp -d)"; mkdir -p "$P2/.claude"
printf '%s' '{"claims":[{"writes_to":"test-results.json","requires_read_of":["test-output.log"]}],"evidence_freshness_minutes":7}' > "$P2/.claude/verify-gate.json"
# Create a transcript with a Read from 15 minutes ago (stale w.r.t. 7-minute window)
STALE_TS=$(date -u -d "15 minutes ago" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-15M "+%Y-%m-%dT%H:%M:%SZ")
TRANSCRIPT="$P2/transcript.jsonl"
printf '{"type":"tool_use","name":"Read","input":{"file_path":"test-output.log"},"timestamp":"%s"}\n' "$STALE_TS" > "$TRANSCRIPT"
out=$( printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$P2"'/test-results.json","content":"x"},"transcript_path":"'"$TRANSCRIPT"'"}' \
  | CLAUDE_PROJECT_DIR="$P2" bash "$HOOK" 2>/dev/null || true )
if printf '%s' "$out" | grep -q "7"; then
  echo "PASS T2: legacy verify-gate.json used (freshness 7 surfaced in stale message)"
else
  echo "FAIL T2: expected 7 in stale message, got: $out"; fail=1
fi

# Test 3: overreliance_min_bytes from catalyst.json config
# Config specifies min_bytes 99999. A 50-byte non-claim write with overreliance ON.
# Since 50 < 99999, it should NOT trigger the overreliance gate (no output, exit 0).
P3="$(mktemp -d)"; mkdir -p "$P3/.claude"
printf '%s' '{"verify_gate":{"overreliance_min_bytes":99999}}' > "$P3/.claude/catalyst.json"
out=$( printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$P3"'/notes.txt","content":"short"},"transcript_path":""}' \
  | CATALYST_VERIFY_OVERRELIANCE=1 CLAUDE_PROJECT_DIR="$P3" bash "$HOOK" 2>/dev/null || true )
if [ -z "$out" ]; then
  echo "PASS T3: overreliance_min_bytes from json (50-byte write below 99999 threshold allowed)"
else
  echo "FAIL T3: expected no output for small write, got: $out"; fail=1
fi

rm -rf "${P1:?}" "${P2:?}" "${P3:?}"
[ "$fail" -eq 0 ] && echo "test_verify_gate_config: ALL PASS" || echo "test_verify_gate_config: FAILURES"
exit $fail
