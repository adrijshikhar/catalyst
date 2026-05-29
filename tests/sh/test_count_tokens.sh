#!/usr/bin/env bash
# Smoke test for scripts/count-tokens.sh real-usage mode.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/count-tokens.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# 1. Transcript with usage objects → sums real tokens (10 + 20 + 5 = 35).
cat > "$TMP/transcript.jsonl" <<'EOF'
{"type":"user","content":"hi"}
{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":5,"cache_creation_input_tokens":0}}}
EOF
got=$(bash "$SCRIPT" "$TMP/transcript.jsonl")
if [ "$got" != "35" ]; then echo "FAIL real-usage: expected 35 got $got"; fail=1; else echo "PASS real-usage (35)"; fi

# 2. Plain text file (no usage) → char heuristic. "abcd" = 4 chars → ceil(4/4)=1.
printf 'abcd' > "$TMP/plain.txt"
got=$(bash "$SCRIPT" "$TMP/plain.txt")
if [ "$got" != "1" ]; then echo "FAIL heuristic: expected 1 got $got"; fail=1; else echo "PASS heuristic (1)"; fi

# 3. JSONL without usage → heuristic, not crash.
echo '{"type":"user","content":"hi"}' > "$TMP/nousage.jsonl"
got=$(bash "$SCRIPT" "$TMP/nousage.jsonl")
if ! [[ "$got" =~ ^[0-9]+$ ]]; then echo "FAIL nousage: non-numeric '$got'"; fail=1; else echo "PASS nousage ($got)"; fi

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
