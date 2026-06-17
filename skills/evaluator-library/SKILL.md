---
name: evaluator-library
description: Use when you need to score or grade an artifact against a rubric with a fresh-context evaluator that never saw how the artifact was made — the anti-self-grade guarantee (generator ≠ evaluator). Ships 6 bundled domains (code-quality, ui-design, prose, security, performance, accessibility), each dispatched through a shared brief builder that enforces the separation. Composes with handoff PIPELINE mode's evaluator stages. Trigger phrases: "dispatch an evaluator", "fresh-context evaluator", "anti-self-grade", "pick a rubric", "score this artifact", "rate the quality", "/evaluator-library", plus domain forms like "code-quality review" or "prose review". Use this skill liberally whenever a generated artifact needs an independent quality score, whenever a pipeline stage is an evaluator, or whenever you are about to grade your own output — under-triggering here lets biased self-grades slip through.
---

# evaluator-library

Reusable, dispatch-by-name evaluators for common subjective domains. Solves the problem that every PIPELINE-mode user was hand-rolling rubrics, leading to inconsistent quality and frequent anti-self-grade violations.

The library does not run the evaluator itself — it builds a brief and the caller (you, or handoff PIPELINE mode) dispatches a fresh Agent with that brief. This preserves the architectural invariant that the evaluator subagent never sees the generator's transcript.

## Bundled rubrics

| Domain | Axes |
|--------|------|
| `code-quality` | correctness, readability, maintainability, test_coverage |
| `ui-design` | coherence, originality, craft, functionality |
| `prose` | clarity, accuracy, brevity, hook |
| `security` | input_validation, authn_authz, secrets_handling, owasp_coverage |
| `performance` | algorithmic, allocation, io, blocking_calls |
| `accessibility` | semantic_html, aria, keyboard_nav, contrast |

All rubrics score 1-5 per axis with anchor descriptions. Pass threshold defaults to ≥4 on all axes; configurable via `.claude/evaluator-library.json`.

## How dispatch works

```
User / PIPELINE → /evaluator-library run <domain> <artifact>
                ↓
                Claude interprets commands/evaluator-library.md
                ↓
                Claude runs scripts/dispatch-evaluator.sh → brief (stdout)
                ↓
                Claude dispatches Agent subagent with brief (fresh context)
                ↓
                Evaluator writes .claude/eval-reports/<domain>-<ts>.md
                ↓
                User / orchestrator reads report → decides next step
```

The brief enforces the anti-self-grade rule by listing it in the Forbidden section. The brief does NOT include any transcript path, session ID, or prior conversation content.

## Customization

`.claude/evaluator-library.json`:

```json
{
  "pass_threshold": 4
}
```

The only config field honored by the dispatcher today is `pass_threshold` (default 4). User-supplied rubric overrides live at `.claude/evaluator-library/evaluators/<domain>.md` — the dispatcher checks the user path first, falls back to plugin-bundled rubric.

## Commands

| Command | What it does |
|---------|-------------|
| `/evaluator-library list` | Show all available domains (bundled + user overrides) |
| `/evaluator-library run <domain> <artifact>` | Dispatch evaluator with fresh context |
| `/evaluator-library run <domain> <artifact> --contract <path>` | Include a sprint contract in the brief (PIPELINE mode) |
| `/evaluator-library show-rubric <domain>` | Print the rubric body — for inspection or copying into a custom rubric |

## When NOT to use

- **Mechanical checks** — lint, type, format. Use the tool directly; no rubric needed.
- **Hard binary outcomes** — does the test pass? Did the build succeed? Use the artifact directly, not a rubric.
- **Single-author quick scratch** — no second opinion needed.

## Anti-patterns

- **Skipping the dispatcher and hand-rolling a brief.** That's the path to anti-self-grade violations. Always go through the dispatcher.
- **Passing the generator's transcript "for context".** Forbidden. The rubric + the artifact are sufficient — that's the architectural promise.
- **Inventing new domains without a rubric file.** The dispatcher fails-fast on missing rubrics — extend the library by adding a new `evaluators/<name>.md`, then add a SKILL entry.
- **Treating the verdict as binding.** The verdict is information; the human (or the orchestrator) decides what to do with it.

## Composition with other Catalyst skills

- `handoff` PIPELINE mode invokes evaluator-library at Synthesize precondition stages. Anti-self-grade rule is reinforced.
- `session-health` will flag a `recovery-spiral` at session end if you repeatedly re-dispatch the same evaluator on the same artifact without acting on the verdict — that's a signal you're stuck.
- `pipeline-templates` bundled templates reference evaluator-library by name for their evaluator stages.

## Model evolution

Assumes evaluator subagents need explicit rubrics. May relax if future models internalize domain rubrics with looser prompting. Review annually per Catalyst convention.
