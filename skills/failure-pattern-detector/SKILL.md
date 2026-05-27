---
name: failure-pattern-detector
description: Use when investigating why an agent session went off the rails, when sessions feel unproductive, or when setting up ambient mode for a project. Installs a Stop hook that scans the session transcript at end-of-session for 6 named failure patterns (instruction-fade, edit-mismatch, stale-read, repeated-tool-call, recovery-spiral, context-drowning) and surfaces each detection with a specific recovery recipe. Composes with handoff RECOVER mode. Trigger phrases: "what went wrong", "session got stuck", "/failure-pattern-detector", "detect failure patterns", "ambient diagnostics".
---

# failure-pattern-detector

Auto-detects 6 named failure modes from the OpenDev paper and surfaces them with recovery recipes after a session ends. Composes with `handoff` RECOVER mode (which is the canonical recovery for several of these patterns).

## Patterns detected (v0.5)

| Pattern | Signal | Recovery recipe |
|---------|--------|-----------------|
| `instruction-fade` | Same user message (first 80 chars) repeated 2+ times in last 10 turns | "Claude is missing instruction X. Consider re-stating in a fresh session (handoff RECOVER)." |
| `context-drowning` | Single tool output >10KB | "Large tool output detected. For next big read, consider subagent dispatch instead of inlining." |
| `edit-mismatch` | 2+ "old_string not found" errors in last 5 turns | "Re-Read the file before next Edit — context is stale." |
| `stale-read` | Edit on file F where F was Written between last Read of F and this Edit | "Re-read F — modified since last Read." |
| `repeated-tool-call` | Same Bash/Read/Grep input 3+ times within 5 turns | "Loop detected on '<command>'. Try a different approach." |
| `recovery-spiral` | 3+ consecutive turns starting with Read on previously-seen file | "Recovery spiral detected. Run /clear, paste handoff Resume prompt, continue." |

## Mechanism

- **Stop hook** at `hooks/Stop-failure-pattern-detect.sh`
- Reads `$CLAUDE_TRANSCRIPT_PATH` once at session end
- Pattern matchers run sequentially (fast — each is a single jq + awk pass)
- Detections appended to `.claude/failure-patterns.log` with timestamp + pattern + recovery
- additionalContext is emitted listing detections for the user / next session to see

## Why Stop hook (not PostToolUse)

PostToolUse fires every tool call — too noisy. Stop fires once per session end — single pass over the full transcript catches patterns that emerged over many turns. Tradeoff: detection is end-of-session, not real-time. v0.6 may add real-time detection if signal warrants.

## Setup

```bash
/failure-pattern-detector install
```

Installs the Stop hook. If Tier 1's `Stop-commit-backstop.sh` is already installed, the two compose — both fire on session end, both emit additionalContext independently. Claude Code runs Stop hooks in parallel.

## Customization

`.claude/failure-pattern-detector.json`:

```json
{
  "enabled_patterns": ["instruction-fade", "edit-mismatch", "stale-read", "repeated-tool-call", "recovery-spiral"],
  "thresholds": {
    "repeated_tool_call_count": 3,
    "repeated_tool_call_window_turns": 5,
    "stale_read_max_turns": 15,
    "edit_mismatch_count": 2,
    "recovery_spiral_count": 3
  },
  "log_path": ".claude/failure-patterns.log"
}
```

Disable a noisy pattern by removing it from `enabled_patterns`.

## Commands

| Command | What it does |
|---------|-------------|
| `/failure-pattern-detector install` | Install the Stop hook |
| `/failure-pattern-detector uninstall` | Remove the Stop hook |
| `/failure-pattern-detector status` | Show the last 10 detections from `.claude/failure-patterns.log` |
| `/failure-pattern-detector enable <pattern>` | Add pattern to `enabled_patterns` in config |
| `/failure-pattern-detector disable <pattern>` | Remove pattern from `enabled_patterns` in config |

## When NOT to use

- **Single-turn sessions** — there's no pattern to detect; the hook is a no-op cost.
- **CI / autonomous runs** — those should fail loudly via test results, not via end-of-session heuristics.
- **Projects where false positives would distract** — disable noisy patterns via config rather than uninstalling the whole skill.

## Anti-patterns

- **Treating detections as proofs.** They're heuristics — the recovery recipe is a suggestion, not a verdict.
- **Disabling all patterns instead of fixing the underlying loop.** If `repeated-tool-call` fires repeatedly, that's a signal worth attending to.
- **Acting on detections during the same session.** Stop hook fires at session end; recipes apply to the NEXT session.
- **Letting the log grow unbounded.** `.claude/failure-patterns.log` is plain-text append; rotate or `git rm` periodically.

## Composition with other Catalyst skills

- `handoff` RECOVER mode is the canonical recovery for `recovery-spiral` and `instruction-fade`.
- `hook-builder`'s lifecycle hooks compose: Stop-commit-backstop AND Stop-failure-pattern-detect both fire on session end, independently.
- `verify-gate` denials are NOT counted as patterns — those are policy-correct blocks, not failure modes.

## Model evolution

Assumes patterns are detectable from transcript heuristics. May relax if Claude Code adds first-class observability that surfaces drift natively. Review annually per Catalyst convention.
