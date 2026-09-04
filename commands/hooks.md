---
description: Report status of Catalyst's two plugin-native hooks (PreCompact → handoff WRITE, SessionStart → handoff READ / auto-render), or scaffold a new hook.
---

Invoke the `hooks` skill.

Recognized sub-commands (parse `$ARGUMENT`):

- `status` — Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks-config.sh status` and print the output verbatim. Do not recompute — the script is the source of truth.
- `disable <precompact|sessionstart>` — Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks-config.sh disable <hook>`. Print the output verbatim.
- `enable <precompact|sessionstart>` — Same with `enable`.
- `new <event> <name>` — Generate `hooks/<event>-<name>.sh` from the canonical bash template (set -euo pipefail, stdin read, jq check, fail-open default, TODO marker).
- `lint <path>` — Read the file and check: matcher patterns (warn if `.*` or empty on a tool event), `set -euo pipefail` present, `command -v jq` check, fail-open default, naming convention (filename starts with a recognized event prefix), `bash -n` syntax.

There is no `install` or `uninstall`. Catalyst's hooks are declared in the
plugin's root `hooks.json` and run from the plugin itself, so installing them
is not a step and they cannot fall out of date. If `$ARGUMENT` is `install` or
`uninstall`, say so and run `status` instead.

If `$ARGUMENT` is empty or unrecognized, summarize the skill: what the two hooks do, how to disable either. Point at `skills/hooks/SKILL.md` for full docs.
