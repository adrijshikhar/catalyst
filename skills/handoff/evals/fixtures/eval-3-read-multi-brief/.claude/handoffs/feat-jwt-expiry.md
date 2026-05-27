# Handoff — 2026-05-23T23:14:00Z
# Key: feat-jwt-expiry

## Resume prompt
> read .claude/handoffs/feat-jwt-expiry.md and continue. next acceptance check: pnpm test src/auth/auth.spec.ts passes 6/6.

## Re-entry instructions
- Resume by: extending the JWT expiry check in src/auth/middleware.ts to allow a small clock-skew leeway window.
- Done when: src/auth/auth.spec.ts:42-78 all 6 pass.
- Read `.claude/PROJECT_STATE.md` ONLY if you need historical context.

## State packet
- **Branch:** feat/jwt-expiry
- **Diff summary:** 2 files, +18/-6 in src/auth/
- **Tests run:** src/auth/auth.spec.ts — 4 of 6 pass
- **Decisions affecting next session:** lib is `jose`; comparison is `<=`; expiry uses `Date.now()` (UTC ms)
- **Rejected paths:** `<` (off-by-one); `new Date()` (allocation in hot path)
- **Open risks:** Clock skew not yet addressed.
- **Next acceptance check:** `pnpm test src/auth/auth.spec.ts` passes 6/6.

## Files to read first
- src/auth/middleware.ts
- src/auth/auth.spec.ts:42-78

## Files to NOT load by default
- PROJECT_STATE.md
- src/users/*
