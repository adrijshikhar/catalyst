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

echo "== count-tokens smoke =="
bash tests/sh/test_count_tokens.sh

echo "All checks passed."
