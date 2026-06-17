#!/usr/bin/env bash
# scripts/catalog.sh — print the Catalyst skill catalog (skill, when-to-use,
# trigger phrases, command). Deterministic, zero model tokens. Fail-open: a
# skill whose SKILL.md lacks frontmatter is listed with blank fields.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$ROOT/skills"
COMMANDS_DIR="$ROOT/commands"

echo "Catalyst skill catalog"
echo

[ -d "$SKILLS_DIR" ] || exit 0

for f in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  name="$(basename "$(dirname "$f")")"
  # description: single plain scalar on one line (lint guarantees no block scalar).
  desc="$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$f")"
  # when-to-use: first sentence (up to the first period followed by space).
  when="${desc%%\. *}"
  # triggers: text after "Trigger phrases:" up to the next sentence boundary, if any.
  trig="$(printf '%s' "$desc" | sed -n 's/.*[Tt]rigger phrases: *//p')"
  [ -n "$trig" ] || trig="—"
  [ -n "$when" ] || when="—"
  if [ -f "$COMMANDS_DIR/$name.md" ]; then
    cmd="/catalyst:$name"
  else
    cmd="(skill only)"
  fi
  echo "$name"
  echo "  When:     $when"
  echo "  Triggers: $trig"
  echo "  Command:  $cmd"
  echo
done
