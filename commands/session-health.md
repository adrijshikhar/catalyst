---
description: Manage the session-health skill — install/uninstall the UserPromptSubmit (per-turn) and Stop (session-end) hooks, view recent alerts and detected failure patterns, toggle patterns on/off.
---

Invoke the `session-health` skill.

Parse `$ARGUMENT` to determine which sub-command to run:

- `install` — Install both hooks into `.claude/settings.json`. Run:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh install UserPromptSubmit UserPromptSubmit-session-health.sh
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh install Stop Stop-session-health.sh
  ```
  Also copy `hooks/lib/` to `.claude/hooks/lib/` so the shared signal library is available.
  Report which files were copied and which settings.json entries were added.
  Both hooks compose with existing UserPromptSubmit/Stop entries — no existing hooks are removed.

- `uninstall` — Remove both hooks. Run:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh uninstall UserPromptSubmit UserPromptSubmit-session-health.sh
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh uninstall Stop Stop-session-health.sh
  ```

- `status` — Print the last 20 entries from `.claude/session-health.log`. If the log
  doesn't exist, say "No alerts or patterns detected yet."
  Also print the effective thresholds currently in force (from `.claude/session-health-watch.json`
  or defaults): advertised tokens, effective fraction, warn threshold, strong threshold.

- `patterns` — List all 6 named failure patterns with their enabled/disabled state from
  `.claude/session-health.json` (or defaults if the file is absent):
  `repeated-tool-call`, `edit-mismatch`, `stale-read`, `recovery-spiral`,
  `instruction-fade`, `context-drowning`.

- `enable <pattern>` — Read `.claude/session-health.json` (create with defaults if missing),
  add `<pattern>` to `enabled_patterns`, write back. Report the change.

- `disable <pattern>` — Read `.claude/session-health.json` (create with defaults if missing),
  remove `<pattern>` from `enabled_patterns`, write back. Report the change.

- (no recognized sub-command or empty) — Summarize what session-health does: the two-hook
  model (per-turn UserPromptSubmit + session-end Stop), the 4 per-turn signals
  (context-pressure at 2 levels) with recalibrated effective-window thresholds,
  the 6 session-end patterns. Point at
  `skills/session-health/SKILL.md` for full docs.
