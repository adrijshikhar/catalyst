#!/usr/bin/env bash
# scripts/test.sh — single local entrypoint for Catalyst's deterministic gate.
# Mirrors the PR-blocking CI lane (Lane A): structure+breadth lint, Python unit
# tests, deterministic eval-snapshot grade, and the functional hook smoke.
# No model, no network, no secrets. Exit non-zero on the first failing stage.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== lint =="
python3 scripts/lint.py

echo "== unit tests =="
python3 -m unittest discover -s tests -v

echo "== eval grade (committed snapshots) =="
python3 scripts/eval-grade.py

echo "== hook functional smoke =="
bash tests/sh/test_hook_smoke.sh
bash tests/sh/test_install_hooks_lib.sh

echo "== count-tokens smoke =="
bash tests/sh/test_count_tokens.sh

echo "== token count from last-assistant usage =="
bash tests/sh/test_token_count.sh

echo "== session-health Stop output schema =="
bash tests/sh/test_session_health_stop_output.sh

echo "== pattern window: Stop matchers scoped to recent tool events =="
bash tests/sh/test_pattern_window.sh

echo "== verify-gate over-reliance rule =="
bash tests/sh/test_verify_gate_overreliance.sh

echo "== session-stats reads live session-health.log =="
bash tests/sh/test_session_stats_logs.sh

echo "== transcript lib: real .message.content[] + flat + fail-open =="
bash tests/sh/test_transcript_lib.sh

echo "All checks passed."
