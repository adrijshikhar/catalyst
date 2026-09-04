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
| Context resets > compaction | `handoff` WRITE/READ — fresh-agent bootstrap from `<main>/.claude/handoffs/<key>.json`. `/handoff list` and `/handoff prune` keep that store honest: one brief accretes per branch, and a merged branch leaves an orphan a recurring branch name would otherwise resolve to |
| Lost-in-the-middle mitigation (re-grounding) | `handoff` REGROUND — read-only mid-session re-injection of goal + locked decisions + next-check |
| Structured artifact handoff (file-based, not conversational) | typed JSON brief schema, shared across all modes. `handoff-render.py --brief` enforces the 30-line subagent ceiling deterministically instead of trusting the model to self-police it |
| Anti-self-grade + pre-coding contract (separate evaluator subagent, done agreed up front) | `handoff` BRIEF — evaluator/reviewer subagents are dispatched as a separate fresh-context Agent; the brief states `done_when` before work starts |
| Lifecycle hooks (PreCompact / SessionStart) | `hooks` skill. Declared once in a root `hooks.json`, read by Claude Code, Codex and Copilot, and run from the plugin cache, so there is no copy to fall behind. `/hooks status` reports what is registered and whether the two advisory hooks are enabled |

### Hosts

Catalyst ships in Claude Code's plugin layout, which Codex and GitHub Copilot read as a legacy format. It does not ship an Agent Plugins root manifest: Codex excludes hooks from Agent Plugins-format packages (`openai/codex` PR #37027), and Catalyst's hooks are the point.

Both advisory hooks (PreCompact, SessionStart) are active on Claude Code as soon as the plugin installs. On Codex they run after a one-time trust approval in the TUI (`/hooks`) — until then they are listed, not executed. On GitHub Copilot (VS Code, Copilot CLI) they are Claude-format compatible per VS Code docs, but unverified. Cursor, Kiro, OpenClaw, Hermes Agent, Grok Bot, NanoClaw need an Agent Plugins root manifest, which Codex forbids alongside hooks; they return the day OpenAI lifts that boundary. Windsurf has no plugin system. Slash commands are Claude Code only; elsewhere the skills are reached by trigger phrase.

---

## Configuration

Everything works with no configuration. When you do want to tune something,
`.claude/catalyst.json` is the single file, and the precedence is
**environment variable > that file > built-in default**:

```json
{
  "handoff": { "stale_hours": 24, "brief_max_lines": 30 },
  "hooks":   { "precompact_prompt": true, "sessionstart_resume": true }
}
```

Environment-variable names derive mechanically — `CATALYST_` plus the dotted key
uppercased with `.` replaced by `_`, so `handoff.stale_hours` is overridden by
`CATALYST_HANDOFF_STALE_HOURS`. There is no lookup table to fall out of date. Each
key falls back to its own default independently — configuring one does not
silently drop another.

One reader per language implements this: `hooks/lib/config.sh` for the hooks, which
are POSIX bash and `jq` only, and `scripts/catalyst_config.py` for the Python
helpers. A parity test holds the two to the same answers, and CI fails if a hook
re-implements the store-path resolution instead of sourcing the shared library.

---

## Design principles

1. **One brief schema, many surfaces.** A session-handoff, a subagent task description, and an evaluator brief are the same shape. Catalyst defines that shape once — and validates it.
2. **Context isolation is cheap; context bleed is expensive.** Briefs cap at 30 lines for subagents — checked by `handoff-render.py --brief`, which exits non-zero and names the oversized sections rather than leaving the ceiling to good intentions. Project narrative is referenced by pointer, never inlined.
3. **Generator ≠ evaluator.** Self-evaluation bias is measured and severe. Catalyst enforces separation as a hard rule in `handoff` BRIEF: evaluator and reviewer subagents are dispatched as a separate fresh-context Agent.
4. **Pre-coding contracts.** Generator + evaluator negotiate "done" before any work happens. Acceptance checks are explicit, verifiable, and locked.
5. **Strip rather than accumulate.** Every primitive is a wager about a model limitation. Review yearly; retire what flagship models grow past.

---

## When complexity earns its place

Every component of every skill encodes an assumption about what the current model can't do reliably on its own. Those assumptions get stress-tested with each new flagship model — scaffolding that no longer earns its complexity gets stripped. The plugin grows opinionated about *when* to add complexity, not just *what* complexity to add.

---

## See also

- [README](../README.md) — install + overview
- Each skill's `SKILL.md` under [`skills/`](../skills) — full trigger conditions + behavior
- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — the Anthropic framework that grounds Catalyst's design
