#!/usr/bin/env bash
# tests/sh/test_verify_gate_overreliance.sh — EDD test for the over-reliance rule.
#
# Tests the opt-in CATALYST_VERIFY_OVERRELIANCE rule that emits a trust-caution
# ("ask") when a Write/Edit of a LARGE diff has NO evidence Read in-window.
#
# Positive test  (flag ON):  hook emits over-reliance caution + permissionDecision "ask"
# Negative test  (flag OFF): hook does NOT emit over-reliance caution (no friction)
#
# The test crafts a minimal synthetic transcript and PreToolUse event that matches
# the hook's actual stdin contract (see PreToolUse-verify-gate.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/PreToolUse-verify-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
fail=0

# ---------------------------------------------------------------------------
# Build a synthetic transcript (JSONL): no Read entries at all.
# The hook reads $TRANSCRIPT_PATH and scans for {"type":"tool_use","name":"Read",...}
# entries. An empty / Read-free transcript means zero evidence in-window.
# ---------------------------------------------------------------------------
TRANSCRIPT="$TMP/transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","content":"implement the feature"}
{"type":"assistant","content":"Sure, let me write it."}
EOF

# ---------------------------------------------------------------------------
# Build a large content string (>= default 4000 bytes) for the Write event.
# We use a Python one-liner so we don't depend on bash string repetition limits.
# ---------------------------------------------------------------------------
LARGE_CONTENT=$(python3 -c "print('x' * 5000)")

# ---------------------------------------------------------------------------
# Positive test — CATALYST_VERIFY_OVERRELIANCE=1
# Event: Write tool, content >= 4000 bytes, no evidence Read in transcript.
# Expected: output contains over-reliance/unverified caution AND
#           permissionDecision == "ask".
# ---------------------------------------------------------------------------
EVENT_POS=$(jq -n \
  --arg tp "$TRANSCRIPT" \
  --arg content "$LARGE_CONTENT" \
  '{
    tool_name: "Write",
    tool_input: {
      file_path: "/tmp/output.py",
      content: $content
    },
    transcript_path: $tp,
    session_id: "test-overreliance"
  }')

OUT_POS=$(printf '%s' "$EVENT_POS" | \
  CATALYST_VERIFY_OVERRELIANCE=1 CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null) || true

# Must contain caution text
if echo "$OUT_POS" | grep -iEq "over-reliance|unverified|no evidence"; then
  echo "PASS positive: over-reliance caution present in output"
else
  echo "FAIL positive: expected over-reliance/unverified/no-evidence caution in output, got: $OUT_POS"
  fail=1
fi

# Must emit permissionDecision "ask"
DECISION_POS=$(echo "$OUT_POS" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || true)
if [ "$DECISION_POS" = "ask" ]; then
  echo "PASS positive: permissionDecision is 'ask'"
else
  echo "FAIL positive: expected permissionDecision 'ask', got: '$DECISION_POS'"
  fail=1
fi

# Output must be valid JSON
if echo "$OUT_POS" | jq -e . >/dev/null 2>&1; then
  echo "PASS positive: output is valid JSON"
else
  echo "FAIL positive: output is not valid JSON: $OUT_POS"
  fail=1
fi

# ---------------------------------------------------------------------------
# Negative test — CATALYST_VERIFY_OVERRELIANCE unset (default OFF)
# Same event, same large content, no evidence — but flag is off.
# Expected: hook does NOT emit the over-reliance caution.
# ---------------------------------------------------------------------------
EVENT_NEG="$EVENT_POS"

OUT_NEG=$(printf '%s' "$EVENT_NEG" | \
  CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null) || true

if echo "$OUT_NEG" | grep -iEq "over-reliance|unverified|no evidence"; then
  echo "FAIL negative: over-reliance caution emitted even when flag is OFF"
  fail=1
else
  echo "PASS negative: no over-reliance caution when CATALYST_VERIFY_OVERRELIANCE is off"
fi

# ---------------------------------------------------------------------------
# Negative test — flag ON but content is SMALL (below threshold)
# Expected: hook does NOT emit over-reliance caution (size threshold not met).
# ---------------------------------------------------------------------------
SMALL_CONTENT="small content under threshold"
EVENT_SMALL=$(jq -n \
  --arg tp "$TRANSCRIPT" \
  --arg content "$SMALL_CONTENT" \
  '{
    tool_name: "Write",
    tool_input: {
      file_path: "/tmp/output.py",
      content: $content
    },
    transcript_path: $tp,
    session_id: "test-overreliance-small"
  }')

OUT_SMALL=$(printf '%s' "$EVENT_SMALL" | \
  CATALYST_VERIFY_OVERRELIANCE=1 CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null) || true

if echo "$OUT_SMALL" | grep -iEq "over-reliance|unverified|no evidence"; then
  echo "FAIL small-content: over-reliance caution emitted for small content"
  fail=1
else
  echo "PASS small-content: no over-reliance caution for content below threshold"
fi

# ---------------------------------------------------------------------------
# Negative test — flag ON, content LARGE, but evidence WAS Read in-window.
# Build transcript with a recent Read entry; hook should allow through.
# ---------------------------------------------------------------------------
TRANSCRIPT_WITH_READ="$TMP/transcript_with_read.jsonl"
NOW_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$TRANSCRIPT_WITH_READ" <<EOF
{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/output.py"},"timestamp":"${NOW_TS}"}
EOF

EVENT_WITH_EVIDENCE=$(jq -n \
  --arg tp "$TRANSCRIPT_WITH_READ" \
  --arg content "$LARGE_CONTENT" \
  '{
    tool_name: "Write",
    tool_input: {
      file_path: "/tmp/output.py",
      content: $content
    },
    transcript_path: $tp,
    session_id: "test-overreliance-with-evidence"
  }')

OUT_WITH_EVIDENCE=$(printf '%s' "$EVENT_WITH_EVIDENCE" | \
  CATALYST_VERIFY_OVERRELIANCE=1 CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null) || true

if echo "$OUT_WITH_EVIDENCE" | grep -iEq "over-reliance|unverified|no evidence"; then
  echo "FAIL evidence-present: over-reliance caution emitted even though evidence was Read"
  fail=1
else
  echo "PASS evidence-present: no over-reliance caution when recent Read evidence exists"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
