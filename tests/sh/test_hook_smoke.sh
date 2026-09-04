#!/usr/bin/env bash
# Functional smoke for every hook: install into a throwaway temp git repo,
# pipe a minimal event, assert it exits 0 and (when it emits) emits valid JSON.
# Temp-git-repo isolation keeps every hook away from the real tree.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
fail=0

cd "$TMP"
git init -q && git config user.email t@e.st && git config user.name test
echo init > f.txt && git add f.txt && git commit -qm init
# Hooks run from the plugin tree directly under hooks.json — no staging.
# SCRIPT_DIR resolves lib/ relative to $0, so invoking "$REPO_ROOT/hooks/<hook>.sh"
# finds "$REPO_ROOT/hooks/lib/" on its own.

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
for hook in "$REPO_ROOT"/hooks/*.sh; do
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
out=$(printf '%s' '{"transcript_path":"","session_id":"smoke"}' | CLAUDE_PROJECT_DIR="$NOGIT" bash "$REPO_ROOT/hooks/PreCompact-handoff-write.sh" 2>/dev/null) || { echo "FAIL PreCompact (no-git): non-zero exit"; fail=1; }
if printf '%s' "$out" | jq -e '.systemMessage | contains("legacy")' >/dev/null 2>&1; then
  echo "PASS PreCompact no-branch (legacy slot, systemMessage, no crash)"
else
  echo "FAIL PreCompact no-branch: expected legacy-slot systemMessage, got: $out"; fail=1
fi
rm -rf "${NOGIT:?}"

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

# Regression: SessionStart-handoff-read auto-RENDERS (not announces) the brief
# when source=clear/compact and a branch-keyed brief exists. Guards the
# lifecycle-collapse feature: the user must not need a third /handoff resume.
SSR="$(mktemp -d)"
( cd "$SSR" && git init -q && git config user.email t@e.st && git config user.name t \
  && echo x > f.txt && git add f.txt && git commit -qm init && git branch -m lifecycle-test )
mkdir -p "$SSR/.claude/handoffs"
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
  | CLAUDE_PROJECT_DIR="$SSR" bash "$REPO_ROOT/hooks/SessionStart-handoff-read.sh" 2>/dev/null) \
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

# Regression (Finding 2): PreCompact-handoff-write.sh and
# SessionStart-handoff-read.sh call jq with no availability check, so under
# `set -euo pipefail` and jq absent from PATH they used to abort with
# "jq: command not found" (exit 127) instead of degrading to inert. Both
# must now fail OPEN: a non-127 exit and no raw jq error leaking to output.
JQMISS_T="$(mktemp -d)"
( cd "$JQMISS_T" && git init -q && git config user.email t@e.st && git config user.name t \
  && echo x > f.txt && git add f.txt && git commit -qm init )
STUB=$(mktemp -d)
for c in bash sh cat printf test grep sed awk mkdir rm dirname basename pwd cd command ls git; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$STUB/$c" 2>/dev/null
done

for hook in PreCompact-handoff-write.sh SessionStart-handoff-read.sh; do
  out=$(printf '%s' '{"transcript_path":"","session_id":"smoke","source":"startup"}' \
    | PATH="$STUB" CLAUDE_PROJECT_DIR="$JQMISS_T" bash "$REPO_ROOT/hooks/$hook" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 127 ]; then
    echo "FAIL $hook (no jq): exited 127"; fail=1
  elif printf '%s' "$out" | grep -qi 'jq: command not found'; then
    echo "FAIL $hook (no jq): raw jq error leaked: $out"; fail=1
  else
    echo "PASS $hook (no jq): failed open (exit $rc), no raw jq error"
  fi
done
rm -rf "${JQMISS_T:?}" "${STUB:?}"

# --- SessionStart must handle ALL FIVE sources ---
# Matcher values are exact-match over startup|resume|clear|compact|fork, and
# hooks.json declares matcher "" so every one reaches this script. An earlier
# design used "startup|clear|compact", which would have silently dropped resume
# and fork. This asserts the script itself copes with each.
S5="$(mktemp -d)"; git -C "$S5" init -q
mkdir -p "$S5/.claude/handoffs"
cat > "$S5/.claude/handoffs/main.json" <<'BRIEF'
{"schema_version":"1","key":"main","timestamp":"2026-09-03T00:00:00Z","mode":"WRITE",
 "resume":{"done_when":"d","resume_by":"r"},
 "state":{"branch":"main","next_acceptance_check":"c",
          "worktree":{"root":"/w","is_linked":false,"git_common_dir":"/w/.git"}}}
BRIEF
git -C "$S5" checkout -q -b main 2>/dev/null || true

for src in startup resume clear compact fork; do
  out=$(printf '{"source":"%s"}' "$src" | CLAUDE_PROJECT_DIR="$S5" \
        bash "$REPO_ROOT/hooks/SessionStart-handoff-read.sh" 2>&1) || true
  if printf '%s' "$out" | grep -q 'hookSpecificOutput'; then
    echo "PASS S5-$src: emits event-correct output"
  else
    echo "FAIL S5-$src: no hookSpecificOutput — source unhandled: $out"; fail=1
  fi
done

# clear/compact auto-render the five load-bearing fields; the other three announce.
out=$(printf '%s' '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$S5" bash "$REPO_ROOT/hooks/SessionStart-handoff-read.sh" 2>&1)
printf '%s' "$out" | grep -q 'Next step' \
  && echo "PASS S5-render: clear auto-renders" \
  || { echo "FAIL S5-render: clear did not auto-render: $out"; fail=1; }
out=$(printf '%s' '{"source":"resume"}' | CLAUDE_PROJECT_DIR="$S5" bash "$REPO_ROOT/hooks/SessionStart-handoff-read.sh" 2>&1)
printf '%s' "$out" | grep -q 'Next step' \
  && { echo "FAIL S5-announce: resume auto-rendered; it should announce only"; fail=1; } \
  || echo "PASS S5-announce: resume announces without rendering"
rm -rf "${S5:?}"

[ "$fail" -eq 0 ] && echo "Failed: 0" || { echo "Failed: 1"; exit 1; }
