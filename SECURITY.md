# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for an
unfixed vulnerability.

- Preferred: open a [GitHub private security advisory](https://github.com/adrijshikhar/catalyst/security/advisories/new).
- Alternative: email the maintainer (see the `author` field in
  [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json)).

Include: affected file(s) and version (`plugin.json` `version` / git tag), a
description of the issue, and a minimal reproduction or proof of concept.

You'll get an acknowledgement within a few days. Fixes ship as a normal patch
release (auto-tagged `vX.Y.Z`); the advisory is published once a fix is
available.

## Supported versions

Catalyst ships from `main`; the latest released tag is the only supported
version. Roll back or pin via `/plugin install catalyst@catalyst@<version>`.

## Scope and threat model

Catalyst is a Claude Code plugin: POSIX-bash hooks + Python scripts + Markdown
skills/commands. It has **no server, no network calls, no authentication, and no
database**. The security-relevant surface is the **lifecycle hooks**, which run
on the end user's machine with their shell privileges and consume event/transcript
JSON.

Hardening already in place:

- **Hooks are network-free** and `set -euo pipefail`, fail-open on infra error.
- **Untrusted input is `jq`-parsed, never shell-`eval`'d.** Transcript/event
  content never reaches a shell command position.
- **Path inputs are sanitized/clamped** — `session_id` is stripped to
  `[A-Za-z0-9_-]`; configurable log paths are clamped inside the project dir.
- **No secrets in the repo or git history**; the release pipeline's token lives
  only in GitHub Actions secrets.
- **CI runs deterministic structural + security validators** (invisible-unicode
  / ASCII-smuggling scan, no-personal-paths, hook-schema, file-ref resolution)
  on every PR via `scripts/lint.py`.

### In scope

- Command injection, path traversal, or arbitrary file write reachable through a
  hook from event/transcript content.
- Secret exposure in tracked files or releases.
- Supply-chain issues in the plugin's own scripts.

### Out of scope

- The release/CI workflow internals (GitHub Actions), which are not shipped to
  plugin users.
- Issues requiring the attacker to already have write access to the user's
  project directory.
- Findings from generic scanners that flag intentional, documented behavior
  (e.g. `2>/dev/null` fail-open in hooks).
