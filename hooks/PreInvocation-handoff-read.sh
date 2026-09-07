#!/usr/bin/env bash
# PreInvocation-handoff-read.sh — Catalyst hooks (Antigravity CLI adapter)
#
# Antigravity has no SessionStart event. Its PreInvocation hook fires before
# EVERY model call with {"invocationNum": N, "workspacePaths": [...], ...}.
# This adapter turns the first invocation of a conversation (invocationNum 0)
# into a SessionStart: it builds the Claude-shaped payload, runs
# SessionStart-handoff-read.sh, and re-emits its additionalContext in
# Antigravity's shape — {"injectSteps": [{"ephemeralMessage": "..."}]}.
# Every later invocation, and any failure, emits {} so the model is never
# force-fed the brief twice. Honours hooks.sessionstart_resume through the
# inner hook. Declared under the "catalyst" key of hooks.json (Antigravity
# reads every top-level key as a named hook; Claude Code and Codex read only
# "hooks"). Antigravity runs hook commands with cwd = the directory holding
# hooks.json, i.e. the plugin root.
#
# Exit codes: 0 always after jq is found (fail-open with {}); 1 if jq missing.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v jq >/dev/null 2>&1; then exit 1; fi
INPUT="$(cat 2>/dev/null || true)"
NUM="$(printf '%s' "$INPUT" | jq -r '.invocationNum // empty' 2>/dev/null || true)"
if [ "$NUM" != "0" ]; then echo '{}'; exit 0; fi
PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // empty' 2>/dev/null || true)"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"
PAYLOAD="$(jq -n --arg cwd "$PROJECT_DIR" '{source: "startup", cwd: $cwd}')"
OUT="$(printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$SCRIPT_DIR/SessionStart-handoff-read.sh" 2>/dev/null || true)"
CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
if [ -z "$CTX" ]; then echo '{}'; exit 0; fi
jq -n --arg ctx "$CTX" '{injectSteps: [{ephemeralMessage: $ctx}]}'
