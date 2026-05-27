---
description: Manage the verify-gate skill — install/uninstall the PreToolUse hook, add custom claim rules, or check status. Routes the user's argument to the appropriate sub-action.
---

Invoke the `verify-gate` skill.

If `$ARGUMENT` is one of the recognized sub-commands, run it. Otherwise, run the skill in its default explanatory mode.

Recognized sub-commands:

- `install` — Run `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh install PreToolUse PreToolUse-verify-gate.sh "Write|Edit"`. Report which file was copied and which settings.json entry was added.
- `uninstall` — Run `bash $CLAUDE_PROJECT_DIR/scripts/install-hooks.sh uninstall PreToolUse PreToolUse-verify-gate.sh`.
- `add <write_path> <read_path>[,<read_path>...]` — Read `.claude/verify-gate.json` (create from default if missing), append a new claim rule, write back. Report the rule added.
- `status` — Read `.claude/verify-gate.json` and print the configured rules. If `$CLAUDE_TRANSCRIPT_PATH` is available, scan recent hook denials and print last 5.

If `$ARGUMENT` is empty or unrecognized, summarize the skill: what verify-gate does, when it fires, how to install. Point at `skills/verify-gate/SKILL.md` for full docs.
