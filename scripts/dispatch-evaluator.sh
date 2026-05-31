#!/usr/bin/env bash
# scripts/dispatch-evaluator.sh — shared evaluator dispatch helper
#
# Builds a fresh-context brief from a domain rubric + artifact, prints it to
# stdout for the caller to hand to the Agent tool. Anti-self-grade rule is
# encoded in the brief text — the dispatcher itself doesn't read transcripts.
#
# Usage:
#   bash scripts/dispatch-evaluator.sh <domain> <artifact-path> [contract-path]
#
# Where:
#   <domain>         = code-quality | ui-design | prose | security | performance | accessibility
#   <artifact-path>  = absolute or repo-relative path to the artifact under evaluation
#   <contract-path>  = optional path to the sprint contract (PIPELINE mode)
#
# Output: brief markdown on stdout. Caller hands to the Agent tool.
#
# Config:
#   $CLAUDE_PROJECT_DIR/.claude/evaluator-library.json — pass_threshold + rubric overrides

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install jq (brew install jq / apt-get install jq) and retry." >&2
  exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DOMAIN="${1:-}"
ARTIFACT="${2:-}"
CONTRACT="${3:-}"

if [ -z "$DOMAIN" ] || [ -z "$ARTIFACT" ]; then
  echo "Usage: dispatch-evaluator.sh <domain> <artifact-path> [contract-path]" >&2
  exit 2
fi

if [ ! -e "$ARTIFACT" ]; then
  echo "ERROR: artifact not found at '$ARTIFACT'." >&2
  exit 4
fi

# Locate the rubric file (user override takes precedence over plugin-bundled)
PLUGIN_RUBRIC="$PROJECT_DIR/skills/evaluator-library/evaluators/$DOMAIN.md"
USER_RUBRIC="$PROJECT_DIR/.claude/evaluator-library/evaluators/$DOMAIN.md"

if [ -f "$USER_RUBRIC" ]; then
  RUBRIC_FILE="$USER_RUBRIC"
elif [ -f "$PLUGIN_RUBRIC" ]; then
  RUBRIC_FILE="$PLUGIN_RUBRIC"
else
  echo "ERROR: rubric not found for domain '$DOMAIN'. Looked at $USER_RUBRIC and $PLUGIN_RUBRIC." >&2
  exit 3
fi

# Resolve pass threshold
CONFIG_FILE="$PROJECT_DIR/.claude/evaluator-library.json"
PASS_THRESHOLD=4
if [ -f "$CONFIG_FILE" ]; then
  PASS_THRESHOLD=$(jq -r '.pass_threshold // 4' "$CONFIG_FILE")
fi

CONTRACT_LINE=""
if [ -n "$CONTRACT" ]; then
  CONTRACT_LINE="- contract: $CONTRACT"
fi

cat <<EOF
## Task
Evaluate the artifact at \`$ARTIFACT\` against the \`$DOMAIN\` rubric.

## Rubric
$(cat "$RUBRIC_FILE")

## Pass threshold
All axes >= $PASS_THRESHOLD. (Configurable via .claude/evaluator-library.json.)

## Inputs (read-only — do NOT modify)
- artifact: $ARTIFACT
$CONTRACT_LINE

## Forbidden
- Reading the generator's transcript (anti-self-grade rule — you must NEVER see how the artifact was produced)
- Modifying any file (you have Read-only access)
- Inventing axes not in the rubric
- Asking the user clarifying questions — score from the artifact alone

## Output
Write a structured report at \`$PROJECT_DIR/.claude/eval-reports/$DOMAIN-\$(date +%s).md\` with:
- One section per axis: score (1-5) + one-sentence rationale
- Overall verdict line: \`VERDICT: PASS\` or \`VERDICT: NEEDS_WORK\`
- For each failing axis, a "Critique" subsection with specific actionable feedback (file:line where applicable)
- DO NOT include the artifact's full content — only references to it
EOF
