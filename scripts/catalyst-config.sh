#!/usr/bin/env bash
# scripts/catalyst-config.sh — CLI over hooks/lib/config.sh, for tests and
# manual inspection. The lib is the implementation; this is only a front door.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/config.sh"

case "${1:-}" in
  get)   catalyst_config_get "${2:?usage: get <dotted.key> [default]}" "${3-}" ;;
  json)  catalyst_config_json "${2:?usage: json <dotted.key>}" ;;
  store) catalyst_store_dir "${2:-$(pwd)}" ;;
  root)  catalyst_project_root "${2:-$(pwd)}" ;;
  *)
    echo "usage: catalyst-config.sh get <key> [default] | json <key> | store [dir] | root [dir]" >&2
    exit 2
    ;;
esac
