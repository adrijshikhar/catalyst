---
name: verify-gate
description: Use when writing test results, build status, deployment status, completion markers, or any "claim of success" artifact. Blocks the write at the OS level via a PreToolUse hook unless an evidence file (test output, build log, etc.) was Read in the same session within a freshness window. Solves optimistic completion bias — agents that claim done without evidence. Use this skill liberally for any project where Claude writes status / results / completion artifacts that downstream consumers (CI, PR reviewers, dashboards) will trust. Trigger phrases: "verify gate", "evidence gate", "/verify-gate", "block unverified claims", "claim without evidence".
---

# verify-gate

A discipline-and-enforcement skill that prevents agents from declaring success without evidence. Implements the pattern shipped by Anthropic in [`cwc-long-running-agents`](https://github.com/anthropics/cwc-long-running-agents/blob/main/hooks/verify-gate.sh) as a `PreToolUse` hook.

The prompt-only version of this rule achieves ~40% adherence (Anthropic measured). The hook-enforced version achieves ~100% because exit code 2 cannot be argued with.

## When it triggers

The PreToolUse hook fires on `Write` and `Edit` tool calls. If the target file matches a configured "claim" rule, the hook checks the session transcript for a corresponding evidence Read within the freshness window (default 10 minutes).

| User writes... | Hook requires recent Read of... |
|---------------|-------------------------------|
| `test-results.json` | `test-output.log`, `vitest-results.xml`, `pytest.xml`, `jest-results.json` |
| `build-status.txt` | `build.log`, `tsc-output.log` |
| any path matching a project-level rule | the configured evidence file(s) |

If no Read on evidence within the window → hook returns `permissionDecision: "deny"` with a structured reason naming the missing evidence. Claude sees the denial and is told what to Read before retrying.

## Setup

```bash
/verify-gate install
```

This copies `PreToolUse-verify-gate.sh` to `.claude/hooks/` and registers it in `.claude/settings.json`. If you have existing PreToolUse hooks, this is additive — they continue to fire.

## Customization

Create `.claude/verify-gate.json` to override the default rules:

```json
{
  "claims": [
    {
      "writes_to": "deployment.log",
      "requires_read_of": ["build.log", "smoke-test.log"]
    },
    {
      "writes_to": "release-notes.md",
      "requires_read_of": ["CHANGELOG.md"]
    }
  ],
  "evidence_freshness_minutes": 15
}
```

The hook matches `writes_to` against the basename of the file being written. Multiple `requires_read_of` entries are OR'd — any one of them satisfies the rule.

## Commands

| Command | What it does |
|---------|-------------|
| `/verify-gate install` | Copy hook to `.claude/hooks/` + register in `.claude/settings.json` |
| `/verify-gate uninstall` | Remove the hook (settings.json cleaned, hook script deleted) |
| `/verify-gate add <write_path> <read_path>[,read_path2,...]` | Append a claim rule to `.claude/verify-gate.json` |
| `/verify-gate status` | List currently configured claim rules + show recent blocks (from session log) |

## What to do when the hook blocks you

The denial response tells you exactly which file to Read. Read it, then retry the write. If the evidence is genuinely missing (e.g., the test never ran), don't trick the hook — actually produce the evidence.

If the evidence is stale (Read >10min ago), re-Read it. The freshness window catches the "I read it an hour ago and a lot has changed" failure mode.

## When NOT to use

- **Pure scratch workflows** — quick prototypes with no claim semantics. No need to gate.
- **Tasks where the writes don't claim anything** — adding a comment to a doc, renaming a variable. The hook only fires on configured claim paths; everything else passes through.
- **CI / autonomous runs** — those should use Anthropic's `cwc-long-running-agents` `/goal` + `verify-gate.sh` directly; this Catalyst version is for interactive workflows.

## Anti-patterns

- **Disabling the hook to "unblock" yourself.** If you're hitting blocks, the system is working. Read the evidence.
- **Configuring overly broad globs in `verify-gate.json`.** Don't block legitimate writes — keep the rule list precise.
- **Setting `evidence_freshness_minutes` very high** (>60). Stale evidence defeats the gate.
- **Manually editing `.claude/settings.json` to remove the hook entry.** Use `/verify-gate uninstall` so settings.json stays valid.

## Composition with other Catalyst skills

- `handoff` writes to `.claude/handoffs/<key>.md` and `.claude/PROJECT_STATE.md`. Those paths are NOT in the default claim list, so handoff writes are never blocked by verify-gate.
- `hook-builder` may install verify-gate as part of `--all`. The two compose cleanly.

## Model evolution

The hook encodes an assumption: prompt-only adherence to "Read before claim" is ~40%. May relax if future models internalize the rule without scaffolding. Review annually per Catalyst convention.
