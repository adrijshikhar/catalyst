---
description: Manage the failure-pattern-detector skill — install/uninstall the Stop hook, view recent detections, toggle patterns. Surfaces OpenDev-paper failure modes (instruction-fade, edit-mismatch, stale-read, repeated-tool-call, recovery-spiral, context-drowning) at session end with specific recovery recipes.
---

Invoke the `failure-pattern-detector` skill.

Recognized sub-commands (parse `$ARGUMENT`):

- `install` — Run `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh install Stop Stop-failure-pattern-detect.sh`. Report which file was copied and which settings.json entry was added.
- `uninstall` — Run `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh uninstall Stop Stop-failure-pattern-detect.sh`.
- `status` — Read `.claude/failure-patterns.log` and print the last 10 detection lines. If the log doesn't exist, say "No detections yet."
- `enable <pattern>` — Read `.claude/failure-pattern-detector.json` (create with defaults if missing), add `<pattern>` to `enabled_patterns` if not already present, write back. Report the change.
- `disable <pattern>` — Read `.claude/failure-pattern-detector.json` (create with defaults if missing), remove `<pattern>` from `enabled_patterns`, write back. Report the change.

Valid pattern names: `instruction-fade`, `edit-mismatch`, `stale-read`, `repeated-tool-call`, `recovery-spiral`, `context-drowning`.

If `$ARGUMENT` is empty or unrecognized, summarize the skill: what failure-pattern-detector does, the 6 patterns, how to install. Point at `skills/failure-pattern-detector/SKILL.md` for full docs.
