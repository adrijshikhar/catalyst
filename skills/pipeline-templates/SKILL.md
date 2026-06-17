---
name: pipeline-templates
description: Use when you want to run a recurring multi-stage pipeline shape by name instead of re-decomposing it each time — an audit, a multi-week feature, a multi-perspective review. Ships 3 executable bundled templates (audit-then-fix, research-plan-implement-review, parallel-review-synthesize) and runs user-saved templates from .claude/pipelines/<name>.md. Trigger phrases: "/pipeline run", "/pipeline list", "run a saved pipeline", "save this pipeline", "audit-then-fix", "research-plan-implement-review", "parallel-review-synthesize", "run a template". Use this skill liberally whenever a task matches a pipeline you have run before, whenever someone asks for "the usual audit or review flow", or whenever you would otherwise hand-decompose a shape Catalyst already ships — re-decomposing a known pipeline is the waste this skill removes.
---

# pipeline-templates

Makes handoff v0.3's save-as-template step useful by adding execution-by-name. Catalyst bundles 3 default templates; users save their own.

## Bundled templates

| Template | When to use | Stages |
|----------|-------------|--------|
| `audit-then-fix` | Codebase audit (security / performance / correctness) followed by fixing top findings | parallel-audit → prioritize → fix → verify |
| `research-plan-implement-review` | Multi-week feature from fuzzy ask to reviewed PR | research → plan → contract → implement → review |
| `parallel-review-synthesize` | One artifact, multiple reviewer angles, unified summary | parallel-review → synthesize |

## Template format

Templates are markdown with a fixed section structure:

```markdown
# Pipeline: <name>

## When to use
<one sentence>

## Decomposition axis
<concern | module | stage>

## Stages
1. **<stage-name>** (parallel | sequential | background)
   - Subagent role: <researcher / planner / generator / evaluator / orchestrator>
   - Inputs: <pointers>
   - Expected output: <artifact shape>
2. ...

## Synthesis
<how the orchestrator combines stage outputs>

## Failure / abort criteria
<conditions under which to stop the pipeline mid-flight>
```

## Lookup order

When `/pipeline run <name>` is invoked, the skill checks:
1. `$CLAUDE_PROJECT_DIR/.claude/pipelines/<name>.md` (user-saved — takes precedence)
2. `$CLAUDE_PROJECT_DIR/skills/pipeline-templates/templates/<name>.md` (plugin-bundled)

User templates override bundled ones with the same name — that's the customization story.

## Execution

`/pipeline run <name>` hands the template to `handoff` PIPELINE mode at step 2 (decompose → route...). The template's stage list IS the decomposition; PIPELINE mode handles BRIEF + dispatch + synthesis per the existing protocol.

`/pipeline run <name> --dry-run` renders the stage plan to stdout and exits without dispatching. Use to inspect what would happen.

## Commands

| Command | What it does |
|---------|-------------|
| `/pipeline list` | List bundled + user templates with their `When to use` line |
| `/pipeline run <name>` | Execute the named template via handoff PIPELINE mode |
| `/pipeline run <name> --dry-run` | Print the stage plan without dispatching |
| `/pipeline save <name>` | Save the just-run pipeline shape to `.claude/pipelines/<name>.md` |

(The `/pipeline` slash command also still supports the original handoff PIPELINE-mode invocation when no `run` / `list` / `save` sub-arg is provided — see `commands/pipeline.md`.)

## When NOT to use

- **One-off pipelines** — if you're not going to run this shape again, no template needed. Just use `/pipeline` directly.
- **Pipelines that span repos** — single-repo only in v0.5. Cross-repo is Tier 4 territory.
- **Templates that auto-run on commit / cron** — that's Tier 4 `multi-agent-coord`.

## Anti-patterns

- **Editing bundled templates in `skills/pipeline-templates/templates/`.** They ship with the plugin; your changes will conflict on update. Save user copies to `.claude/pipelines/` instead.
- **Templates with evaluator stages that bypass `evaluator-library`.** Use the dispatch helper — anti-self-grade is preserved by going through it.
- **Templates with >7 stages.** Indicator that the decomposition is wrong; split into two templates with a hand-off artifact between them.
- **Saving every pipeline as a template.** Only save the ones you'd actually re-run. Otherwise `.claude/pipelines/` becomes a graveyard.

## Composition with other Catalyst skills

- `handoff` PIPELINE mode is the runtime — pipeline-templates is the catalog.
- `evaluator-library` is referenced by template evaluator stages. The dispatcher enforces fresh context.
- `session-health` may flag a `recovery-spiral` at session end if a template fails to converge — that's a signal the template needs review.

## Model evolution

Assumes templates speed up common workflows. May retire if future Claude Code internalizes pipeline shapes natively (no template lookup needed). Review annually per Catalyst convention.
