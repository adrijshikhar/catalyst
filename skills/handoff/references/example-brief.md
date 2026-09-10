# Example — good WRITE brief (tier-2 branch)

Moved out of SKILL.md 2026-09-06; the shape is enforced by `brief.schema.json` + `handoff-validate.py`, this file is for humans reading the skill.


**Bad** (vague, unvalidated):

```json
{ "key": "feat-jwt-expiry", "notes": "worked on auth, some tests failing, continue tomorrow" }
```

**Good** (typed, validated, immediately actionable):

```json
{
  "schema_version": "1",
  "key": "feat-jwt-expiry",
  "timestamp": "2026-05-24T01:42:00Z",
  "mode": "WRITE",
  "resume": {
    "done_when": "pnpm test src/auth/auth.spec.ts passes 6/6",
    "resume_by": "fix JWT expiry check in src/auth/middleware.ts — add leeway parameter"
  },
  "state": {
    "branch": "feat/jwt-expiry",
    "next_acceptance_check": "pnpm test src/auth/auth.spec.ts passes 6/6",
    "worktree": {"root": "/repo", "is_linked": false, "git_common_dir": "/repo/.git"},
    "diff_summary": "2 files, +18/-6 in src/auth/",
    "tests": [{"cmd": "pnpm test src/auth/auth.spec.ts", "result": "fail"}],
    "decisions": [
      "Use Date.now() (UTC ms) — not new Date() (alloc in hot path)",
      "JWT lib is jose, not jsonwebtoken (see PROJECT_STATE.md 2026-05-20 [feat-jwt-expiry])",
      "Operator is <= not <"
    ],
    "rejected_paths": ["< operator (off-by-one)", "new Date() (alloc)"],
    "open_risks": ["Clock skew not addressed yet"]
  },
  "files_read_first": [
    {"path": "src/auth/middleware.ts", "why": "file under repair"},
    {"path": "src/auth/auth.spec.ts", "why": "failing tests at lines 42-78"}
  ],
  "files_skip": [
    {"path": "src/auth/types.ts", "why": "stable"},
    {"path": "src/users/*", "why": "unrelated"},
    {"path": ".catalyst/PROJECT_STATE.md", "why": "historical only; decisions above are binding"}
  ]
}
```

The good version answers "what do I do first, what is success, what should I not redo" — and `handoff-validate.py` confirms it is complete before it reaches disk.

---
