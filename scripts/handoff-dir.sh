#!/usr/bin/env bash
# handoff-dir.sh — print the centralized handoffs dir for the repo containing
# $1 (default: cwd). Thin wrapper: the resolver itself lives in
# hooks/lib/config.sh so hooks and scripts share one implementation.
# Worktree-aware — anchors at the main checkout (parent of the shared .git).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/config.sh"
catalyst_store_dir "${1:-$(pwd)}"
