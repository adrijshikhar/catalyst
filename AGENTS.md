# Catalyst — agent instructions

Catalyst gives a long-running coding session a typed **handoff brief** that survives compaction and session boundaries, plus two lifecycle hooks that write and re-render it. This file is the host-agnostic summary; the skills carry the detail.

## Skills

- **`handoff`** — WRITE a schema-validated brief (`.claude/handoffs/<branch>.json` in the main worktree), READ it back as a resume prompt, REGROUND mid-session, RECOVER a degraded brief, BRIEF a subagent. Invoke when ending a session, before compaction, when switching context, or when briefing a subagent.
- **`hooks`** — status and authoring for the two hooks below.

## Hooks (where the host runs them)

- `PreCompact` → prompt a handoff WRITE before context is summarized.
- `SessionStart` → render the brief back on `clear`/`compact`; announce it on `startup`/`resume`.

Hosts without these events (or without hooks) still get the skills; invoke `handoff` by name.

## Requirements

Python 3 for the handoff scripts (`scripts/handoff-*.py`, standard library only). `jq` for the hooks.

Source and per-host install: https://github.com/adrijshikhar/catalyst
