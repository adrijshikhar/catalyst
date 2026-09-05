---
description: Invoke handoff. Task-delegation requests route to BRIEF for native subagent dispatch or external task-file delivery. Otherwise no argument runs WRITE with a branch-derived key. Keywords — "brief" → BRIEF; "read" / "resume" → READ; "recover" / "rebuild" → RECOVER; "reground" → REGROUND; "list" → inventory; "prune" → propose orphan deletion. Other arguments are explicit checkpoint keys.
---

Invoke the `handoff` skill.

Task delegation takes precedence over checkpoint WRITE: “handoff this to a
subagent” routes to BRIEF native dispatch; “handoff this to Codex” (or another
separate agent/session) routes to BRIEF external delivery. External output is a
file under `.catalyst/tasks/` plus a short launch prompt unless the user explicitly
requests inline. A plain “prepare a brief” does not request dispatch.

The helper scripts ship inside the plugin, NOT the user's project. Resolve them from the plugin root and reuse this as `$SCR` in the skill's commands (`handoff-dir.sh`, `handoff-validate.py`, `handoff-render.py`, `handoff_paths.py`):

```
${CLAUDE_PLUGIN_ROOT}/scripts
```

If the user passed a single recognized keyword as `$ARGUMENT`, route to that mode:

- `read` or `resume` → READ mode (load existing brief for current branch / key)
- `recover` or `rebuild` → RECOVER mode (rebuild a degraded brief)
- `reground` → REGROUND mode (read-only re-injection of the current key's load-bearing fields: goal, locked decisions, files to keep in view — no disk write, no mismatch checks)
- `brief` → BRIEF mode (prepare a task brief; use the user's surrounding request to select native dispatch or external file delivery)
- `list` → run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/handoff-list.py` and print the output verbatim (read-only inventory)
- `prune` → run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/handoff-prune.py` (dry run), print the candidates, and ask the user to confirm before re-running with `--apply`. NEVER pass `--apply` without explicit confirmation.
- any other non-empty value → WRITE mode with `$ARGUMENT` as the tier-1 explicit key (writes the validated JSON brief to `<store>/<argument>.json`)
- empty argument → WRITE mode, resolve key via the ladder (branch → legacy)

Then follow the skill's procedure for the selected mode exactly. Confirm to the user which mode + which key was used.
