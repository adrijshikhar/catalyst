#!/usr/bin/env bash
# build.sh — regenerate the README handoff demo GIF with VHS.
#
# Honest demo: sets up a throwaway git repo with a real typed brief in the
# centralized store, then the tape runs the REAL handoff-render.py to resume.
# Every line of output in the GIF is genuine script output, not mocked.
#
# Requires: vhs (brew install vhs), python3, git, jq.
# Usage: bash assets/demo/build.sh   (run from the repo root)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEMO=/tmp/catalyst-demo

rm -rf "$DEMO"
mkdir -p "$DEMO/.claude/handoffs" "$DEMO/skills/handoff"
# Physical path — render.py resolves symlinks (/tmp -> /private/tmp on macOS);
# store the resolved path so worktree.git_common_dir matches and no false mismatch.
DEMO="$(cd "$DEMO" && pwd -P)"
cp -r "$REPO/scripts" "$DEMO/scripts"
cp "$REPO/skills/handoff/brief.schema.json" "$DEMO/skills/handoff/brief.schema.json"

# Real git repo on the brief's branch so render() finds no branch/repo mismatch.
git -C "$DEMO" init -q
git -C "$DEMO" config user.email demo@catalyst.dev
git -C "$DEMO" config user.name catalyst-demo
git -C "$DEMO" checkout -q -b feat/jwt-expiry
echo "demo" > "$DEMO/README.md"
git -C "$DEMO" add -A && git -C "$DEMO" commit -qm "init"

# A realistic brief — what /catalyst:handoff WROTE before the last /compact.
cat > "$DEMO/.claude/handoffs/feat-jwt-expiry.json" <<EOF
{
  "schema_version": "1",
  "key": "feat-jwt-expiry",
  "timestamp": "2026-05-30T18:40:00Z",
  "mode": "WRITE",
  "resume": {
    "done_when": "pnpm test auth.spec.ts 6/6 green",
    "resume_by": "add the clock-skew leeway window to the expiry check"
  },
  "state": {
    "branch": "feat/jwt-expiry",
    "next_acceptance_check": "expiry uses <= (not <); 60s leeway honored",
    "worktree": { "root": "$DEMO", "is_linked": false, "git_common_dir": "$DEMO/.git" },
    "tests": [{ "cmd": "pnpm test auth.spec.ts", "result": "fail" }],
    "decisions": ["jose, not jsonwebtoken", "compare with <= to fix off-by-one"],
    "rejected_paths": ["new Date() in hot path — allocation churn"]
  },
  "files_read_first": [
    { "path": "src/auth/middleware.ts", "why": "the expiry check to extend" }
  ]
}
EOF

# Validate the brief is real and well-formed before we film it.
python3 "$DEMO/scripts/handoff-validate.py" "$DEMO/.claude/handoffs/feat-jwt-expiry.json"

cd "$REPO"
vhs assets/demo/handoff.tape
echo "wrote assets/demo/handoff.gif"
