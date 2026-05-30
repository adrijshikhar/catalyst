---
description: Invoke the handoff skill. With no argument, runs WRITE mode and resolves the key via the 3-tier ladder (explicit name → current branch → legacy). With "$ARGUMENT" provided, uses it as the explicit tier-1 key. Special keywords — "read" / "resume" → READ mode; "recover" / "rebuild" → RECOVER mode.
---

Invoke the `handoff` skill.

The helper scripts ship inside the plugin, NOT the user's project. Resolve them from the plugin root and reuse this as `$SCR` in the skill's commands (`handoff-dir.sh`, `handoff-validate.py`, `handoff-render.py`, `handoff_paths.py`):

```
${CLAUDE_PLUGIN_ROOT}/scripts
```

If the user passed a single recognized keyword as `$ARGUMENT`, route to that mode:

- `read` or `resume` → READ mode (load existing brief for current branch / key)
- `recover` or `rebuild` → RECOVER mode (rebuild a degraded brief)
- `reground` → REGROUND mode (read-only re-injection of the current key's load-bearing fields: goal, locked decisions, files to keep in view — no disk write, no mismatch checks)
- any other non-empty value → WRITE mode with `$ARGUMENT` as the tier-1 explicit key (writes the validated JSON brief to `<store>/<argument>.json`)
- empty argument → WRITE mode, resolve key via the ladder (branch → legacy)

Then follow the skill's procedure for the selected mode exactly. Confirm to the user which mode + which key was used.
