---
description: Install / inspect / configure the session-degradation-watch UserPromptSubmit hook that monitors 4 signals (context %, repeated tool call, stale read, contradiction) and suggests handoff WRITE before the wall.
---

Parse `$ARGUMENT` to determine which sub-command to run:

- `install` — Invoke the `session-degradation-watch` skill in INSTALL mode. Use `scripts/install-hooks.sh` to wire `UserPromptSubmit-session-degradation-watch.sh` into `.claude/settings.json`. Composes with any existing UserPromptSubmit hooks (Tier 1's orient hook).

- `status` — Invoke the skill in STATUS mode. Print the last 20 entries from `.claude/session-degradation.log` plus the current config from `.claude/session-degradation-watch.json` (or defaults if absent).

- `threshold <signal> <value>` — Invoke the skill in THRESHOLD mode. Update `.claude/session-degradation-watch.json` to set the named threshold. `<signal>` is one of `warn`, `strong`, `force`, `repeated_count`, `repeated_window`, `stale_turns`. `<value>` is a number.

- (no recognized sub-command) — Default: print usage to the user.
