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

The design principles that shape this harness — one schema/many surfaces, no context bleed, generator ≠ evaluator, pre-coding contracts, strip rather than accumulate, and the rest — are the plugin's foundation and live in one canonical place: **[docs/PRINCIPLES.md](./PRINCIPLES.md)**. Every component of every skill encodes an assumption about what the current model can't do reliably alone; those assumptions get stress-tested at each flagship model and stripped when they no longer earn their complexity. The map above shows *what* each primitive is; PRINCIPLES.md is *why* it exists and *when* it should be retired.

---

## See also

- [PRINCIPLES](./PRINCIPLES.md) — the plugin's foundation: core principles, strict rules, change-validation checklist
- [README](../README.md) — install + overview
- Each skill's `SKILL.md` under [`skills/`](../skills) — full trigger conditions + behavior
- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — the Anthropic framework that grounds Catalyst's design
