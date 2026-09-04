# Contributing to Catalyst

Thanks for considering a contribution. Catalyst stays small and focused on harness engineering for Claude Code — typed context handoffs and the lifecycle hooks that fire them. Skills outside that scope are better as their own plugin.

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

The body is the instructions Claude follows when the skill activates. Target ≤500 lines. If you need more, split into `references/` files the skill can read on demand.

## Slash commands

Optional. Live at `commands/<name>.md`. Should be thin wrappers that invoke a skill — the skill holds the logic.

## CI

Every PR runs the deterministic gate — structure and breadth lint, Python unit tests, committed eval-snapshot grading, and the hook/installer/catalog/config/transcript shell suites. No model, no API key. Run exactly what CI runs:

```bash
bash scripts/test.sh
```

## Commits

Conventional commits with a mandatory scope when the change is feature-specific:

- `feat(<scope>):`, `fix(<scope>):`, `refactor(<scope>):`, `test(<scope>):`, `docs(<scope>):`, `ci:`, `chore:`
- Imperative mood, lowercase after the colon, no trailing period
- An em dash `—` separates the headline from any elaboration
- Breaking changes take a `!` suffix (`feat(scope)!:`) and a `BREAKING CHANGE:` footer
- Never add `Co-Authored-By` lines
- `[skip ci]` belongs only on the automated version-bump commit

## Releases

Releases are manual. `.github/workflows/release.yml` is `workflow_dispatch`-only. `scripts/release.sh` bumps the **patch** version only, so a minor or major release is hand-tagged — see "Release pipeline" in `CLAUDE.md`.

## Style

- Skill instructions: clear, imperative, no fluff. Claude is the audience.
- Code: standard formatting, no comments unless the why is non-obvious.
- Commits: `<type>: <description>` — feat, fix, docs, refactor, test, chore.

## License

By contributing you agree your work ships under the MIT license.
