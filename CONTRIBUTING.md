# Contributing to Catalyst

Thanks for considering a contribution. Catalyst stays small and focused on agent orchestration + harness efficiency. Skills outside that scope are better as their own plugin.

## Proposing a new skill

Open an issue using the **New skill proposal** template before writing code. Include:

- **Problem** — what pain point does this skill solve?
- **Trigger conditions** — when should Claude auto-invoke it?
- **Behavior** — what does it do, in order?
- **Why this plugin** — why does it fit Catalyst vs a standalone plugin?

Skills are accepted when they have clear triggers, narrow scope, and demonstrably reduce token usage or improve agent reliability.

## Skill structure

Every skill lives at `skills/<name>/SKILL.md` with YAML frontmatter:

```yaml
---
name: <kebab-case-name>
description: <single line — when to invoke and what it does>
---
```

The body is the instructions Claude follows when the skill activates. Keep it under 300 lines. If you need more, split into `references/` files the skill can read on demand.

## Slash commands

Optional. Live at `commands/<name>.md`. Should be thin wrappers that invoke a skill — the skill holds the logic.

## CI

PRs run frontmatter + JSON validation. Local check:

```bash
python3 scripts/lint.py
```

## Style

- Skill instructions: clear, imperative, no fluff. Claude is the audience.
- Code: standard formatting, no comments unless the why is non-obvious.
- Commits: `<type>: <description>` — feat, fix, docs, refactor, test, chore.

## License

By contributing you agree your work ships under the MIT license.
