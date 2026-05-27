---
description: Manage Catalyst lifecycle hooks (PreCompact → handoff WRITE, SessionStart → handoff READ, Stop → commit backstop, UserPromptSubmit → repo orientation). Install / uninstall pre-built hooks, scaffold new ones from templates, or lint existing hooks. Routes the user's argument to the appropriate sub-action.
---

Invoke the `hook-builder` skill.

Recognized sub-commands (parse `$ARGUMENT`):

- `install <event>` — Install the named pre-built hook. Map event names to files:
  - `PreCompact` → `PreCompact-handoff-write.sh`
  - `SessionStart` → `SessionStart-handoff-read.sh`
  - `Stop` → `Stop-commit-backstop.sh`
  - `UserPromptSubmit` → `UserPromptSubmit-orient.sh`
  Run `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh install <event> <hook-file>`.
- `install --all` — Install all four lifecycle hooks via four sequential calls.
- `uninstall <event>` — `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh uninstall <event> <hook-file>`
- `uninstall --all` — Remove all four.
- `new <event> <name>` — Generate `hooks/<event>-<name>.sh` from the canonical bash template (set -euo pipefail, stdin read, jq check, TODO marker).
- `lint <path>` — Read the file and check: matcher patterns (warn if `.*` or empty), `set -euo pipefail` present, `command -v jq` check, fail-open default, naming convention (filename starts with recognized event prefix), `bash -n` syntax.
- `status` — Read `.claude/settings.json`, list which Catalyst-known hooks are currently installed.

If `$ARGUMENT` is empty or unrecognized, summarize the skill: what hook-builder does, what the four pre-built hooks accomplish, how to install. Point at `skills/hook-builder/SKILL.md` for full docs.
