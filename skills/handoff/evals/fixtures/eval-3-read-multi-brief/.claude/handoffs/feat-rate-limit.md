# Handoff — 2026-05-22T18:20:00Z
# Key: feat-rate-limit

## Resume prompt
> read .claude/handoffs/feat-rate-limit.md and continue. next acceptance check: rate-limit middleware accepts a per-route override.

## Re-entry instructions
- Resume by: adding a per-route override to `src/middleware/rate-limit.ts`.
- Done when: existing rate-limit tests pass AND new per-route override test passes.

## State packet
- **Branch:** feat/rate-limit
- **Diff summary:** 1 file, +24/-2 in src/middleware/
- **Tests run:** none yet
- **Decisions affecting next session:** sliding window stays; per-route is opt-in via decorator
- **Rejected paths:** token-bucket (too heavy for our use case)
- **Open risks:** Decorator stacking semantics with auth middleware unverified.
- **Next acceptance check:** `pnpm test src/middleware/rate-limit.spec.ts` passes including the new test.

## Files to read first
- src/middleware/rate-limit.ts

## Files to NOT load by default
- PROJECT_STATE.md
- src/auth/*
