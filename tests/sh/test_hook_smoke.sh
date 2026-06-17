#!/usr/bin/env bash
# Functional smoke for every hook: install into a throwaway temp git repo,
# pipe a minimal event, assert it exits 0 and (when it emits) emits valid JSON.
# Temp-git-repo isolation prevents Stop-commit-backstop touching the real tree.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
fail=0

cd "$TMP"
git init -q && git config user.email t@e.st && git config user.name test
echo init > f.txt && git add f.txt && git commit -qm init
mkdir -p .claude/hooks
cp "$REPO_ROOT"/hooks/*.sh .claude/hooks/ 2>/dev/null || true
chmod +x .claude/hooks/*.sh

# Per-event JSON output schema. `hookSpecificOutput.additionalContext` is only
# valid for UserPromptSubmit / PostToolUse / SessionStart. PreCompact and Stop
# MUST use top-level `systemMessage`; PreToolUse uses hookSpecificOutput with
# permissionDecision. Emitting the wrong shape fails Claude Code's validator.
# This guard caught (and now prevents recurrence of) the Stop + PreCompact bugs.
event_for_hook() {
  case "$1" in
    UserPromptSubmit-*) echo UserPromptSubmit ;;
    PostToolUse-*)      echo PostToolUse ;;
    PostToolBatch-*)    echo PostToolBatch ;;
    SessionStart-*)     echo SessionStart ;;
    PreToolUse-*)       echo PreToolUse ;;
    PreCompact-*)       echo PreCompact ;;
    Stop-*|SubagentStop-*) echo Stop ;;
    *)                  echo unknown ;;
  esac
}

EVENT='{"transcript_path":"","session_id":"smoke","cwd":"'"$TMP"'"}'
for hook in .claude/hooks/*.sh; do
  name="$(basename "$hook")"
  out=$(printf '%s' "$EVENT" | CLAUDE_PROJECT_DIR="$TMP" bash "$hook" 2>/dev/null) || {
    echo "FAIL $name: non-zero exit"; fail=1; continue; }
  if [ -n "$out" ]; then
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      echo "FAIL $name: emitted non-JSON: $out"; fail=1; continue
    fi
    # Schema: hooks whose event forbids hookSpecificOutput must not emit it.
    ev="$(event_for_hook "$name")"
    case "$ev" in
      PreCompact|Stop)
        if printf '%s' "$out" | jq -e 'has("hookSpecificOutput")' >/dev/null 2>&1; then
          echo "FAIL $name: $ev forbids hookSpecificOutput (use systemMessage): $out"; fail=1
        else
          echo "PASS $name (valid $ev JSON, no hookSpecificOutput)"
        fi
        ;;
      *)
        echo "PASS $name (valid JSON)"
        ;;
    esac
  else
    echo "PASS $name (no output, exit 0)"
  fi
done

# Regression: PreCompact must NOT crash on $KEY-unbound in a NON-git dir
# (no branch → legacy slot). Catches the set -u unbound-variable bug.
NOGIT="$(mktemp -d)"
mkdir -p "$NOGIT/.claude/hooks"
cp "$REPO_ROOT/hooks/PreCompact-handoff-write.sh" "$NOGIT/.claude/hooks/"
out=$(printf '%s' '{"transcript_path":"","session_id":"smoke"}' | CLAUDE_PROJECT_DIR="$NOGIT" bash "$NOGIT/.claude/hooks/PreCompact-handoff-write.sh" 2>/dev/null) || { echo "FAIL PreCompact (no-git): non-zero exit"; fail=1; }
if printf '%s' "$out" | jq -e '.systemMessage | contains("legacy")' >/dev/null 2>&1; then
  echo "PASS PreCompact no-branch (legacy slot, systemMessage, no crash)"
else
  echo "FAIL PreCompact no-branch: expected legacy-slot systemMessage, got: $out"; fail=1
fi
rm -rf "${NOGIT:?}"

# Regression: the verify-gate fractional-second timestamp normalization must
# yield a parseable timestamp on THIS host (macOS BSD date or GNU date).
# Mirrors the hook's normalization + parse; guards the macOS fail-open bug (#2).
READ_TS="2024-01-01T00:00:00.123Z"
case "$READ_TS" in *.*) READ_TS="${READ_TS%.*}Z" ;; esac
if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$READ_TS" "+%s" >/dev/null 2>&1 \
   || date -u -d "$READ_TS" "+%s" >/dev/null 2>&1; then
  echo "PASS verify-gate fractional-timestamp normalizes + parses ($READ_TS)"
else
  echo "FAIL verify-gate: normalized timestamp '$READ_TS' still unparseable on this host"; fail=1
fi

# Regression: handoff-dir.sh resolves the CENTRALIZED store from a linked worktree.
CWT_MAIN="$(mktemp -d)"
CWT_MAIN_R="$(cd "$CWT_MAIN" && pwd -P 2>/dev/null || pwd)"
(cd "$CWT_MAIN_R" && git init -q && git config user.email t@e.st && git config user.name t && echo x>f && git add -A && git commit -qm init)
CWT_PARENT="$(mktemp -d)"
CWT_LINK="$CWT_PARENT/wt"
git -C "$CWT_MAIN_R" worktree add -q "$CWT_LINK" -b wt-store-test >/dev/null 2>&1
got=$(bash "$REPO_ROOT/scripts/handoff-dir.sh" "$CWT_LINK")
want="$CWT_MAIN_R/.claude/handoffs"
if [ "$got" = "$want" ]; then
  echo "PASS centralized-store from worktree"
else
  echo "FAIL centralized-store: got $got want $want"; fail=1
fi
git -C "$CWT_MAIN_R" worktree remove --force "$CWT_LINK" 2>/dev/null || true
rm -rf "${CWT_MAIN_R:?}" "${CWT_PARENT:?}"

# Regression: Stop-commit-backstop must emit a VALID Stop payload (systemMessage,
# NOT hookSpecificOutput) when the tree is dirty. The clean-repo smoke loop above
# never reaches this output path.
SCB="$(mktemp -d)"
(cd "$SCB" && git init -q && git config user.email t@e.st && git config user.name t && echo a > a.txt && git add a.txt && git commit -qm init && echo b >> a.txt)
mkdir -p "$SCB/.claude/hooks"
cp "$REPO_ROOT/hooks/Stop-commit-backstop.sh" "$SCB/.claude/hooks/"
rm -f /tmp/catalyst-scb-scb  # Clean up any lingering marker from prior runs
out=$(printf '%s' '{"transcript_path":"","session_id":"scb","cwd":"'"$SCB"'"}' | CLAUDE_PROJECT_DIR="$SCB" bash "$SCB/.claude/hooks/Stop-commit-backstop.sh" 2>/dev/null) || { echo "FAIL Stop-commit-backstop (dirty): non-zero exit"; fail=1; }
if printf '%s' "$out" | jq -e '.systemMessage | contains("working tree")' >/dev/null 2>&1 \
   && ! printf '%s' "$out" | grep -qi 'session ending' \
   && ! printf '%s' "$out" | jq -e 'has("hookSpecificOutput")' >/dev/null 2>&1; then
  echo "PASS Stop-commit-backstop dirty-tree (reworded, no 'session ending', no hookSpecificOutput)"
else
  echo "FAIL Stop-commit-backstop dirty-tree: expected reworded msg, got: $out"; fail=1
fi
# De-noise: a SECOND run with the SAME dirty state must emit nothing (suppressed).
out2=$(printf '%s' '{"transcript_path":"","session_id":"scb","cwd":"'"$SCB"'"}' | CLAUDE_PROJECT_DIR="$SCB" bash "$SCB/.claude/hooks/Stop-commit-backstop.sh" 2>/dev/null) || true
if [ -z "$out2" ]; then
  echo "PASS Stop-commit-backstop de-noise (unchanged dirty state → silent)"
else
  echo "FAIL Stop-commit-backstop de-noise: re-emitted on unchanged state: $out2"; fail=1
fi
rm -f /tmp/catalyst-scb-scb
rm -rf "${SCB:?}"

# Regression I1: uninstall of a session-health hook must NOT reap lib/ when a
# verify-gate hook is still present (verify-gate sources lib/transcript.sh).
I1_DIR="$(mktemp -d)"
(cd "$I1_DIR" && git init -q && git config user.email t@e.st && git config user.name t && echo x>f && git add -A && git commit -qm init)
mkdir -p "$I1_DIR/.claude/hooks/lib"
# Simulate install: session-health + verify-gate hooks and the shared lib
touch "$I1_DIR/.claude/hooks/UserPromptSubmit-session-health.sh"
touch "$I1_DIR/.claude/hooks/PreToolUse-verify-gate.sh"
echo '#!/bin/sh' > "$I1_DIR/.claude/hooks/lib/transcript.sh"
echo '{"hooks":{}}' > "$I1_DIR/.claude/settings.json"
# Uninstall session-health — lib must survive because verify-gate is still present
CLAUDE_PROJECT_DIR="$I1_DIR" HOOKS_SRC_DIR="$REPO_ROOT/hooks" \
  bash "$REPO_ROOT/scripts/install-hooks.sh" uninstall UserPromptSubmit UserPromptSubmit-session-health.sh >/dev/null
if [ -f "$I1_DIR/.claude/hooks/lib/transcript.sh" ]; then
  echo "PASS I1: lib/transcript.sh survives session-health uninstall when verify-gate remains"
else
  echo "FAIL I1: lib/transcript.sh was reaped while verify-gate hook was still present"; fail=1
fi
rm -rf "${I1_DIR:?}"

# Regression: SessionStart-handoff-read auto-RENDERS (not announces) the brief
# when source=clear/compact and a branch-keyed brief exists. Guards the
# lifecycle-collapse feature: the user must not need a third /handoff resume.
SSR="$(mktemp -d)"
( cd "$SSR" && git init -q && git config user.email t@e.st && git config user.name t \
  && echo x > f.txt && git add f.txt && git commit -qm init && git branch -m lifecycle-test )
mkdir -p "$SSR/.claude/hooks" "$SSR/.claude/handoffs"
cp "$REPO_ROOT/hooks/SessionStart-handoff-read.sh" "$SSR/.claude/hooks/"
cat > "$SSR/.claude/handoffs/lifecycle-test.json" <<'JSON'
{
  "schema_version": "1",
  "key": "lifecycle-test",
  "mode": "WRITE",
  "resume": { "resume_by": "RESUME_BY_MARKER step", "done_when": "DONE_WHEN_MARKER" },
  "state": {
    "next_acceptance_check": "ACCEPT_MARKER",
    "open_risks": ["RISK_MARKER one"]
  },
  "files_read_first": [ { "path": "READ_PATH_MARKER.md", "why": "WHY_MARKER" } ],
  "files_skip": [],
  "timestamp": "2026-06-17T00:00:00Z"
}
JSON
ssr_out=$(printf '%s' '{"source":"clear","session_id":"ssr","cwd":"'"$SSR"'"}' \
  | CLAUDE_PROJECT_DIR="$SSR" bash "$SSR/.claude/hooks/SessionStart-handoff-read.sh" 2>/dev/null) \
  || { echo "FAIL SessionStart render-on-clear: non-zero exit"; fail=1; }
ssr_ctx=$(printf '%s' "$ssr_out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if printf '%s' "$ssr_ctx" | grep -q 'RESUME_BY_MARKER' \
   && printf '%s' "$ssr_ctx" | grep -q 'DONE_WHEN_MARKER' \
   && printf '%s' "$ssr_ctx" | grep -q 'ACCEPT_MARKER' \
   && printf '%s' "$ssr_ctx" | grep -q 'RISK_MARKER' \
   && printf '%s' "$ssr_ctx" | grep -q 'READ_PATH_MARKER' \
   && ! printf '%s' "$ssr_ctx" | grep -qi 'if the user wants to resume'; then
  echo "PASS SessionStart render-on-clear (5 fields rendered, no announce)"
else
  echo "FAIL SessionStart render-on-clear: expected rendered fields, got: $ssr_ctx"; fail=1
fi
rm -rf "${SSR:?}"

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
