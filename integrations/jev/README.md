# Optional Jev verification suite

This standalone integration suite provides semantic verification for Catalyst
using TypeSafe Jev. It is outside Catalyst's bundled `skills/` directory: installing
Catalyst does not install these skills, connect to Jev, or require an API key.

Skills in this suite:
- **`verify-handoff`**: Checks checkpoint claims against supplied evidence through
  TypeSafe Jev `jev_verify` during handoff `WRITE`.
- **`verify-task`**: Evaluates code changes, completion claims, and test evidence
  using TypeSafe Jev `jev_gate` before accepting delegated task returns (`BRIEF` mode).
- **Semantic commit-drift verification**: Analyzes landed commits during `READ`
  resume to detect conflicts with locked decisions or next acceptance checks.

## Install separately

Install Catalyst normally and configure a Jev MCP server exposing `jev_verify`
and `jev_gate` in your agent host **using your own Jev API key**. Credentials belong
in your host's MCP configuration or secret store, never in Catalyst's project config,
handoffs, tasks, or narrative. Catalyst ships no API key, shared account, or
credential proxy; this integration does not provision a server or credentials.
See [TypeSafe's documentation](https://docs.typesafe.ai/) for Jev setup.

From this checkout, copy the skills into your host's user skill directory.
For Codex:

```bash
mkdir -p ~/.agents/skills/verify-handoff ~/.agents/skills/verify-task
cp integrations/jev/verify-handoff/SKILL.md ~/.agents/skills/verify-handoff/SKILL.md
cp integrations/jev/verify-task/SKILL.md ~/.agents/skills/verify-task/SKILL.md
```

For Claude Code, use `~/.claude/skills/` instead:

```bash
mkdir -p ~/.claude/skills/verify-handoff ~/.claude/skills/verify-task
cp integrations/jev/verify-handoff/SKILL.md ~/.claude/skills/verify-handoff/SKILL.md
cp integrations/jev/verify-task/SKILL.md ~/.claude/skills/verify-task/SKILL.md
```

Reload skills or start a new session as required by the host, then ask:

> Use verify-handoff to write a Catalyst checkpoint with Jev verification.
> Use verify-task to audit the completed task in .catalyst/tasks/<task>.md.

## Opt in for a project

To verify normal WRITE handoffs and enable semantic drift checks, merge this setting
into `.catalyst/config.json` in the repository's main worktree, preserving existing
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

With `"jev"` enabled:
- Catalyst invokes the separately installed `verify-handoff` skill once before
  publishing each WRITE checkpoint.
- Delegated task completions in `BRIEF` mode route through `verify-task` to
  audit the worker's patch and test logs with `jev_gate`.
- When `READ` resumes on a branch where new commits landed (`commits_since > 0`),
  Catalyst analyzes whether the commits conflict with locked decisions.

The hooks themselves make no network calls. Missing configuration, `"off"`,
or unreadable configuration leaves automatic verification disabled; unknown
values are reported and skipped. This setting does not install the skills or
the Jev MCP server. It enables submission of relevant evidence to the Jev
connection configured in your host, subject to project data-sharing rules.

Without opt-in, ordinary handoffs stay unchanged. On a Jev failure, operations
fail open safely: checkpoints are saved with an explicit “verification not performed”
risk, and task audits report manual checklist status. Evidence sent to Jev
is limited to relevant excerpts permitted by the project's data-sharing rules.
Verdicts are advisory and never replace schema validation or actual tests.

To disable automatic verification, set `handoff.verification` to `"off"`.
Remove the copied skill directories to uninstall.
Behavioral scenarios and their test procedure live in
[verify-handoff/evals](verify-handoff/evals/evals.md) and
[verify-task/evals](verify-task/evals/evals.md).
