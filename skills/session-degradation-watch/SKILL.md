---
name: session-degradation-watch
description: Use when a long Claude Code session approaches context budget, falls into a repeated-tool-call loop, edits a file it Read many turns ago, or contradicts a prior project decision. Installs a UserPromptSubmit hook that monitors 4 signals every turn and surfaces the most urgent alert as additionalContext. Closes the auto-trigger gap that handoff v0.3 left open. Composes with Tier 1's orient hook. Trigger phrases — "/session-degradation-watch", "context is full", "I'm degrading", "stuck in a loop", "monitor context", "auto-suggest handoff". Use this skill liberally on any project running multi-hour or multi-day Claude Code sessions.
---

# session-degradation-watch

Surfaces context degradation BEFORE the wall. Suggests handoff WRITE at graduated thresholds. Detects loops and stale reads in-session.

## Why this exists

`handoff` v0.3 ships WRITE / RECOVER modes that solve degradation **recovery** — but they're explicit. Tier 1's `hook-builder` makes PreCompact / SessionStart / Stop ambient, but not the moment when context is silently getting hot. `session-degradation-watch` fills the gap: fires every turn via UserPromptSubmit, surfaces an alert BEFORE the agent hits the wall.

## The 4 signals

| Signal | Threshold | Action |
|--------|-----------|--------|
| **Context %** | 60% → warn, 75% → strong, 85% → force | "Call handoff WRITE — context at X%" |
| **Repeated tool call** | Same Bash/Read/Grep input ×3 in 5 turns | "Loop on '<X>'. Try different approach." |
| **Stale read** | Edit on file whose Read was >15 turns ago | "Re-Read <file> — modified or stale" |
| **Contradiction** | Last assistant message contradicts a `Decision:` line in `.claude/PROJECT_STATE.md` (string-level `use X not Y` check) | "Conflicts with decision '<X>'. Verify before proceeding." |

Only the most urgent alert fires per turn — single-message bar. Order of urgency: context FORCE > context STRONG > contradiction > stale read > repeated tool call > context WARN.

## Mechanism

- **UserPromptSubmit hook** at `hooks/UserPromptSubmit-session-degradation-watch.sh`
- Fires on every user prompt
- Reads `transcript_path` from hook input JSON
- Counts approximate tokens (chars / 4 — char-count heuristic by default; opt-in tiktoken via `CATALYST_TIKTOKEN=1`)
- Checks each signal against config thresholds
- Emits `hookSpecificOutput.additionalContext` with the most urgent alert
- Logs every alert to `.claude/session-degradation.log` for retrospection

## Why UserPromptSubmit (not Stop)

Stop fires too late — session is ending. Real-time signals need real-time surfacing. UserPromptSubmit gives the agent a chance to ACT on the warning in its next turn.

## Composition with other Catalyst hooks

- **Tier 1 `UserPromptSubmit-orient.sh`** — injects repo orientation. Composes additively: both hooks fire on UserPromptSubmit; each adds its own context. Claude Code shows both.
- **Tier 2 `Stop-failure-pattern-detect.sh`** — end-of-session retrospection. Overlaps with this skill on repeated-tool-call + stale-read, but at different lifecycle stages: this skill surfaces real-time; Tier 2 surfaces at session-end. Both write to separate logs.
- **handoff WRITE mode** — when this skill recommends "call handoff WRITE", the agent invokes `/catalyst:handoff` (no arg) to checkpoint state. This skill suggests; it never auto-recovers (per spec — issue #60248 showed in-loop recovery doesn't work).

## Configuration

`.claude/session-degradation-watch.json`:

```json
{
  "context_thresholds": {"warn": 60, "strong": 75, "force": 85},
  "repeated_tool_call_count": 3,
  "repeated_tool_call_window_turns": 5,
  "stale_read_max_turns": 15,
  "check_contradiction_with_project_state": true,
  "log_path": ".claude/session-degradation.log"
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `context_thresholds.warn` | 60 | % at which to emit a warn-level alert |
| `context_thresholds.strong` | 75 | % at which to escalate to strong recommendation |
| `context_thresholds.force` | 85 | % at which to issue a force-now alert |
| `repeated_tool_call_count` | 3 | Number of identical tool calls in window before alert |
| `repeated_tool_call_window_turns` | 5 | Window size (turns) for repeated-call check |
| `stale_read_max_turns` | 15 | Turns elapsed since last Read of a file before Edit is "stale" |
| `check_contradiction_with_project_state` | true | If true, scan PROJECT_STATE.md for "use X not Y" decisions and flag contradictions |
| `log_path` | `.claude/session-degradation.log` | Where to append alerts |

## Commands

| Command | What it does |
|---------|-------------|
| `/session-degradation-watch install` | Install the UserPromptSubmit hook into `.claude/settings.json` (composes with existing UserPromptSubmit entries) |
| `/session-degradation-watch status` | Print the last 20 entries from `.claude/session-degradation.log` |
| `/session-degradation-watch threshold <signal> <value>` | Update a threshold in `.claude/session-degradation-watch.json` |

## When NOT to use

- **Short sessions** (<30 turns) — overhead doesn't pay back. Install for multi-hour sessions.
- **Projects without a PROJECT_STATE.md** — contradiction signal becomes a no-op. Other 3 signals still useful.
- **CI / non-interactive runs** — UserPromptSubmit never fires; hook is inert. No harm but no benefit.

## Anti-patterns

- **Loud alerts with no actionable recommendation.** Every alert must name the next step (call handoff WRITE, re-Read X, try different approach). Generic alerts are a critique failure.
- **Auto-recovery in-loop.** Issue #60248 measured that in-loop recovery doesn't work. This skill SUGGESTS; the agent decides. Never auto-call handoff.
- **Multiple alerts per turn.** Pick the most urgent. Pile-up alerts get ignored.
- **Hardcoded thresholds.** All thresholds must be configurable per-project via `.claude/session-degradation-watch.json`.

## Model evolution

Assumes the model doesn't natively know when it's degrading. May relax substantially if future Claude has internal "I'm losing the thread" signals or a native context budget warning. Review annually per Catalyst convention.
