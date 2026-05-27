# Catalyst

> Harness engineering for Claude Code — skills that turn the model into a long-running, reliable system.

Catalyst is a Claude Code plugin grounded in **[harness engineering](https://www.anthropic.com/engineering/harness-design-long-running-apps)** — the architectural patterns Anthropic itself uses to ship reliable agentic applications. The plugin treats Claude not as a single chat but as a system that needs scaffolding for context resets, structured artifact handoffs, multi-agent orchestration, and explicit evaluator/generator separation.

Every component of every skill in Catalyst encodes an assumption about what the current model can't do reliably on its own. Those assumptions get stress-tested with each new flagship model — scaffolding that no longer earns its complexity gets stripped. The plugin grows opinionated about *when* to add complexity, not just *what* complexity to add.

## Skills

| Skill | Status | Purpose |
|-------|--------|---------|
| [`handoff`](./skills/handoff/SKILL.md) | v0.3 | Structured context transfer for sessions, subagents, and pipelines. Four modes (WRITE / READ / RECOVER / BRIEF) plus PIPELINE orchestration. Feature-keyed, paste-and-go resume prompts, anti-self-grade guardrails. |
| [`verify-gate`](./skills/verify-gate/SKILL.md) | v0.4 | PreToolUse hook + skill that blocks "claim success" writes (test-results, build-status, deployment artifacts) unless evidence file was Read first. Port of Anthropic's `verify-gate.sh` pattern from `cwc-long-running-agents`. Solves optimistic completion bias. |
| [`hook-builder`](./skills/hook-builder/SKILL.md) | v0.4 | Pre-built lifecycle hooks (PreCompact / SessionStart / Stop / UserPromptSubmit) that wire `handoff` into the session lifecycle. Turns Catalyst from explicit to ambient. Plus authoring helper for new hooks. |
| [`evaluator-library`](./skills/evaluator-library/SKILL.md) | v0.5 | 6 bundled domain rubrics (code-quality, ui-design, prose, security, performance, accessibility) dispatched via a shared brief builder that enforces anti-self-grade. Composes with handoff PIPELINE mode evaluator stages. |
| [`failure-pattern-detector`](./skills/failure-pattern-detector/SKILL.md) | v0.5 | Stop hook + skill that scans the session transcript at end-of-session for 6 OpenDev failure patterns (instruction-fade, edit-mismatch, stale-read, repeated-tool-call, recovery-spiral, context-drowning) and surfaces each with a specific recovery recipe. |
| [`pipeline-templates`](./skills/pipeline-templates/SKILL.md) | v0.5 | 3 bundled executable pipeline templates (audit-then-fix, research-plan-implement-review, parallel-review-synthesize) + `/pipeline run / list / save / --dry-run` extension. Closes the loop on handoff v0.3's save-as-template step. |
| [`brain-bridge`](./skills/brain-bridge/SKILL.md) | v0.6 | MCP adapter wrapper that pulls Company Brain (gbrain / brAIn / codebase-memory-mcp) context into handoff PIPELINE BRIEFs as pointers — never inlined content. 3 bundled adapters. Configurable token budget + relevance threshold. Catalyst becomes the connective tissue between the knowledge layer and the harness. |
| [`session-degradation-watch`](./skills/session-degradation-watch/SKILL.md) | v0.6 | UserPromptSubmit hook + skill that monitors 4 signals (context %, repeated tool call, stale read, contradiction with PROJECT_STATE) every turn and surfaces the most urgent alert as additionalContext. Closes the auto-trigger gap that handoff v0.3 left open. Composes with Tier 1's orient hook. |

More skills land here as the harness matures. Roadmap focuses on patterns the Anthropic framework names: sprint contracts, GAN-style iterate loops, evaluator-generator separation, live application testing (Playwright MCP integration), context-budget watchers.

## What's in the harness

Catalyst's first skill maps to Anthropic's primitives:

| Anthropic primitive | Where Catalyst implements it |
|---------------------|------------------------------|
| Context resets > compaction | `handoff` WRITE/READ modes — fresh-agent bootstrap from `.claude/handoffs/<key>.md` |
| Structured artifact handoff (file-based, not conversational) | brief schema, shared across all four modes |
| Specialized multi-agent (planner / generator / evaluator) | PIPELINE mode canonical role triad |
| Sprint contracts (pre-coding done agreement) | PIPELINE mode contract negotiation step |
| Anti-self-grade (separate evaluator subagent) | PIPELINE mode rule + anti-pattern entry |
| GAN-inspired iterate loops for subjective domains | PIPELINE mode optional loop pattern |
| Gradable rubrics for subjective domains | eval-harness contract at `skills/handoff/evals/evals.md` |
| Evidence-first writes (verify-gate.sh) | `verify-gate` skill (Tier 1) |
| Lifecycle hooks (PreCompact / SessionStart / Stop) | `hook-builder` skill (Tier 1) |
| Pre-built evaluator rubrics (code/ui/prose/security/perf/a11y) | `evaluator-library` skill (Tier 2) |
| End-of-session failure-pattern surfacing (OpenDev paper patterns) | `failure-pattern-detector` skill (Tier 2) |
| Executable saved pipeline templates | `pipeline-templates` skill (Tier 2) |
| Brain / knowledge-layer context injection (MCP) | `brain-bridge` skill (Tier 3) |
| Real-time degradation surfacing (issue #58373 / #60248) | `session-degradation-watch` skill (Tier 3) |

## Install

Catalyst is its own one-plugin marketplace. From inside Claude Code:

```
/plugin marketplace add adrijshikhar/catalyst
/plugin install catalyst@catalyst
```

That registers the marketplace and installs the `catalyst` plugin. Skills become available immediately.

## Usage

After install, invoke skills explicitly or let Claude auto-trigger them:

- **Explicit:** `/handoff` to write a feature-keyed brief, `/handoff resume` to load one, `/pipeline` to orchestrate multi-stage work
- **Auto:** When you end a session, switch context, approach context limits, brief a subagent, or describe a multi-stage task, Claude triggers the right mode of `handoff`

See each skill's `SKILL.md` for full trigger conditions and behavior.

## Design principles

1. **One brief schema, many surfaces.** A session-handoff, a subagent task description, and a pipeline-stage contract are the same shape. Catalyst defines that shape once.
2. **Context isolation is cheap; context bleed is expensive.** Briefs cap at 30 lines for subagents. Project narrative is referenced by pointer, never inlined.
3. **Generator ≠ evaluator.** Self-evaluation bias is measured and severe. Catalyst enforces separation as a primary anti-pattern in PIPELINE mode.
4. **Pre-coding sprint contracts.** Generator + evaluator negotiate "done" before any work happens. Acceptance checks are explicit, verifiable, and locked.
5. **Strip rather than accumulate.** Every primitive is a wager about a model limitation. Review yearly; retire what flagship models grow past.

## Why "Catalyst"

A catalyst accelerates a reaction without being consumed. These skills accelerate Claude's work without crowding the main context — they activate when needed, do their job, then step out of the way.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Skill proposals welcome via GitHub issues using the `new-skill` template. Proposals should ground themselves in a specific harness-engineering pattern from the [Anthropic article](https://www.anthropic.com/engineering/harness-design-long-running-apps) or call out the assumption about model limitations they encode.

## References

- [Harness Engineering for Long-Running Agentic Applications](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Anthropic's framework that grounds Catalyst's design
- [Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents.md) — context isolation primitives Catalyst builds on
- Reddit thread on first-class handoffs in Claude workflows — the community pattern Catalyst codifies in the `handoff` skill

## License

MIT — see [LICENSE](./LICENSE).
