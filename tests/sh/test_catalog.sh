#!/usr/bin/env bash
# scripts/catalog.sh lists every skill with When/Triggers/Command, and is fail-open.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/catalog.sh"
fail=0

out=$(bash "$SCRIPT" 2>/dev/null) || { echo "FAIL catalog: non-zero exit"; fail=1; }

# Header + label lines present
printf '%s' "$out" | grep -q 'Catalyst skill catalog' || { echo "FAIL: missing header"; fail=1; }
for label in 'When:' 'Triggers:' 'Command:'; do
  printf '%s' "$out" | grep -q "$label" || { echo "FAIL: missing label $label"; fail=1; }
done

# Every current skill listed
for s in handoff verify-gate hooks evaluator-library pipeline-templates session-health; do
  printf '%s' "$out" | grep -q "^$s\$" || { echo "FAIL: skill $s not listed"; fail=1; }
done

# A command-backed skill shows its /catalyst:<name>; assert for evaluator-library
printf '%s' "$out" | grep -q '/catalyst:evaluator-library' || { echo "FAIL: evaluator-library command not shown"; fail=1; }

# Fail-open: a temp skills tree with a frontmatter-less SKILL.md still exits 0
TMP="$(mktemp -d)"; mkdir -p "$TMP/scripts" "$TMP/skills/broken" "$TMP/commands"
cp "$SCRIPT" "$TMP/scripts/catalog.sh"
printf 'no frontmatter here\n' > "$TMP/skills/broken/SKILL.md"
if bash "$TMP/scripts/catalog.sh" >/dev/null 2>&1; then echo "PASS fail-open (broken frontmatter, exit 0)"; else echo "FAIL: aborted on broken frontmatter"; fail=1; fi
rm -rf "${TMP:?}"

[ "$fail" -eq 0 ] && echo "test_catalog: ALL PASS" || echo "test_catalog: FAILURES"
exit $fail
