# Optional Jev handoff verification

This standalone skill checks checkpoint claims against supplied evidence through
TypeSafe Jev. It is outside Catalyst's bundled `skills/` directory: installing
Catalyst does not install this skill, connect to Jev, or require an API key.

## Install separately

Install Catalyst normally and configure a Jev MCP server exposing `jev_verify`
in your agent host **using your own Jev API key**. Credentials belong in your
host's MCP configuration or secret store, never in Catalyst's project config,
handoffs, or narrative. Catalyst ships no API key, shared account, or credential
proxy; this integration does not provision a server or credentials.
See [TypeSafe's documentation](https://docs.typesafe.ai/) for Jev setup.

From this checkout, copy the skill into your host's user skill directory.
For Codex:

```bash
mkdir -p ~/.agents/skills/verify-handoff
cp integrations/jev/verify-handoff/SKILL.md ~/.agents/skills/verify-handoff/SKILL.md
```

For Claude Code, use `~/.claude/skills/verify-handoff/` instead. Reload skills
or start a new session as required by the host, then ask:

> Use verify-handoff to write a Catalyst checkpoint with Jev verification.

## Opt in for a project

To verify normal WRITE handoffs, merge this setting into
`.catalyst/config.json` in the repository's main worktree, preserving existing
settings. Use Catalyst's `handoff_paths.py --init` before creating that file so
the storage directory is ignored by Git.

```json
{"handoff": {"verification": "jev"}}
```

The default is `"off"`. The existing configuration precedence applies:
`CATALYST_HANDOFF_VERIFICATION` overrides the project setting. For example,
`CATALYST_HANDOFF_VERIFICATION=off` disables automatic verification in that
agent process. A direct request to verify or skip verification takes precedence
for that handoff and does not change the saved setting.

With `"jev"` enabled, Catalyst invokes the separately installed `verify-handoff`
skill once before publishing each WRITE checkpoint, including a WRITE requested
by the pre-compaction hook. READ, RECOVER, REGROUND, and BRIEF are unchanged.
The hooks themselves make no network calls. Missing configuration, `"off"`,
or unreadable configuration leaves automatic verification disabled; unknown
values are reported and skipped. This setting does not install the skill or
the Jev MCP server. It enables submission of relevant evidence to the Jev
connection configured in your host, subject to project data-sharing rules.

Without opt-in, ordinary handoffs stay unchanged. On a Jev failure, the checkpoint is still
saved with an explicit “verification not performed” risk. Evidence sent to Jev
is limited to relevant excerpts permitted by the project's data-sharing rules.
Verdicts are advisory and never replace schema validation or actual tests.

To disable automatic verification, set `handoff.verification` to `"off"`.
Remove the copied skill directory to uninstall. If verification remains enabled
after uninstalling, Catalyst saves the checkpoint with a missing-verifier notice.
Behavioral scenarios and their test procedure live in
[verify-handoff/evals](verify-handoff/evals/evals.md).
