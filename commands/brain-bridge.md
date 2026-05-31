---
description: Query a configured Company Brain (gbrain / brAIn / codebase-memory-mcp) for pointers to inject into a handoff PIPELINE BRIEF, OR configure the backend, OR check status. Pointers only — never inlined content.
---

Parse `$ARGUMENT` to determine which sub-command to run:

- `query "<phrase>"` — Invoke the `brain-bridge` skill in QUERY mode. Read `.claude/brain-bridge.json` for backend + config. Pipe the configured backend's raw output through `${CLAUDE_PLUGIN_ROOT}/skills/brain-bridge/adapters/<backend>.sh` (the adapters ship in the plugin, not the user's project) and print the normalized JSON to the user.

- `configure <backend>` — Invoke the `brain-bridge` skill in CONFIGURE mode. Prompt for endpoint, write `.claude/brain-bridge.json` with the chosen backend + sensible defaults.

- `status` — Invoke the `brain-bridge` skill in STATUS mode. Print the currently configured backend, the endpoint, and the last 10 entries from `.claude/brain-bridge.log` (if present).

- (no recognized sub-command) — Default: print usage to the user.
