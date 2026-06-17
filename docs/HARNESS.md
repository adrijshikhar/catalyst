# Catalyst — the harness, in depth

The deep dive behind the [README](../README.md): how a handoff brief is shaped, how every skill maps to Anthropic's harness-engineering primitives, the design principles, and the philosophy that decides *when* a primitive earns its place.

If you just want to install and use Catalyst, the [README](../README.md) is enough. Read on if you want to understand *why* it's built this way.

---

## Anatomy of a handoff

WRITE produces a typed, validated brief (rejected if fields are missing or mistyped — that's the point):

```json
{
  "schema_version": "1",
  "key": "feat-jwt-expiry",
  "timestamp": "2026-05-30T10:00:00Z",
  "mode": "WRITE",
  "resume": { "done_when": "pnpm test auth.spec.ts 6/6",
              "resume_by": "re-read middleware, finish expiry check" },
  "state": {
    "branch": "feat/jwt-expiry",
    "next_acceptance_check": "expiry uses <= not <",
    "worktree": { "root": "/repo", "is_linked": false, "git_common_dir": "/repo/.git" },
    "tests": [{ "cmd": "pnpm test", "result": "fail" }]
  }
}
```

READ renders it back into a resume prompt the next session acts on directly — with guards that refuse to resume a brief from a different branch or repo:

```
# Resume — feat-jwt-expiry

## Resume prompt
> resume handoff 'feat-jwt-expiry': … next acceptance check: expiry uses <= not <.

## Summary
- Branch: feat/jwt-expiry
- Done when: pnpm test auth.spec.ts 6/6
- Next acceptance check: expiry uses <= not <
```

Briefs are stored once per feature key in the **main worktree** (`<main>/.claude/handoffs/<key>.json`), so every linked worktree shares one store keyed by branch — resume any feature from any worktree.

---

## What's in the harness

Catalyst maps directly to Anthropic's primitives:

| Anthropic primitive | Where Catalyst implements it |
|---------------------|------------------------------|
| Context resets > compaction | `handoff` WRITE/READ — fresh-agent bootstrap from `<main>/.claude/handoffs/<key>.json` |
| Lost-in-the-middle mitigation (re-grounding) | `handoff` REGROUND — read-only mid-session re-injection of goal + locked decisions + next-check |
| Session fission (split braided work into isolated sessions) | `handoff` SPLIT — N self-contained briefs from one degraded session, interactive confirm |
| Structured artifact handoff (file-based, not conversational) | typed JSON brief schema, shared across all modes |
| Specialized multi-agent (planner / generator / evaluator) | PIPELINE mode canonical role triad |
| Sprint contracts (pre-coding done agreement) | PIPELINE mode contract negotiation step |
| Anti-self-grade (separate evaluator subagent) | PIPELINE mode rule + `evaluator-library` dispatch guard |
| GAN-inspired iterate loops for subjective domains | PIPELINE mode optional loop pattern |
| Gradable rubrics for subjective domains | `evaluator-library` + eval-harness contracts at `skills/*/evals/` |
| Evidence-first writes (verify-gate.sh) | `verify-gate` skill |
| Trust calibration / over-reliance on large unverified agent output | `verify-gate` opt-in over-reliance rule |
| Lifecycle hooks (PreCompact / SessionStart / Stop / UserPromptSubmit) | `hook-builder` skill |
| Pre-built evaluator rubrics (code/ui/prose/security/perf/a11y) | `evaluator-library` skill |
| End-of-session failure-pattern surfacing | `session-health` skill (Stop hook) |
| Executable saved pipeline templates | `pipeline-templates` skill |
| Real-time degradation surfacing | `session-health` skill (UserPromptSubmit hook) |

---

## Design principles

1. **One brief schema, many surfaces.** A session-handoff, a subagent task description, and a pipeline-stage contract are the same shape. Catalyst defines that shape once — and validates it.
2. **Context isolation is cheap; context bleed is expensive.** Briefs cap at 30 lines for subagents. Project narrative is referenced by pointer, never inlined.
3. **Generator ≠ evaluator.** Self-evaluation bias is measured and severe. Catalyst enforces separation as a primary anti-pattern in PIPELINE mode.
4. **Pre-coding sprint contracts.** Generator + evaluator negotiate "done" before any work happens. Acceptance checks are explicit, verifiable, and locked.
5. **Strip rather than accumulate.** Every primitive is a wager about a model limitation. Review yearly; retire what flagship models grow past.

---

## When complexity earns its place

Every component of every skill encodes an assumption about what the current model can't do reliably on its own. Those assumptions get stress-tested with each new flagship model — scaffolding that no longer earns its complexity gets stripped. The plugin grows opinionated about *when* to add complexity, not just *what* complexity to add.

---

## See also

- [README](../README.md) — install + overview
- Each skill's `SKILL.md` under [`skills/`](../skills) — full trigger conditions + behavior
- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — the Anthropic framework that grounds Catalyst's design
