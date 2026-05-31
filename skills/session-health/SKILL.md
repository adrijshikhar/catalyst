---
name: session-health
description: Use when a long session is degrading, approaching the effective context window, looping on the same tool call, contradicting earlier decisions, or when you want to surface what went wrong at the end of a session. Fires on two timing layers — per-turn via UserPromptSubmit and session-end via Stop — over a shared signal library. Trigger phrases: "/session-health", "context is full", "I'm degrading", "stuck in a loop", "monitor context", "what went wrong", "the model got dumber", "detect failure patterns", "ambient diagnostics". Use this skill liberally on any multi-hour session — install once and it monitors silently, surfacing exactly one alert per turn when a signal fires.
---

# session-health

Two-timing detector for long Claude Code sessions. Monitors degradation in real time
(per-turn, UserPromptSubmit) and audits failure patterns at the end (Stop), both over
a shared POSIX bash + jq signal library. Merges `session-degradation-watch` (v0.6)
and `failure-pattern-detector` (v0.5) into a single ambient skill.

## Why this exists

Context rot is not a vibe. GPT-4o falls from a 99.3% baseline to 69.7% at just 32K
tokens — well inside its 128K advertised window ([NoLiMa, ICML 2025](https://arxiv.org/abs/2502.05167)).
RULER finds only half of 17 long-context models maintain satisfactory performance at 32K
despite claiming 32K+ support ([RULER, COLM 2024](https://arxiv.org/abs/2404.06654)).
The effective usable window is typically 50–70% of the advertised limit. Bigger windows
don't fix this — the mechanism is an intrinsic attention budget that every token draws
from (n² pairwise relationships) and a U-shaped positional bias that under-attends middle
content ([Lost in the Middle, TACL 2024](https://arxiv.org/abs/2307.03172)).

The practical fix is harness-layer detection + structured reset. This skill detects;
`/catalyst:handoff reground` resets. Neither step works alone.

## Two-timing model

```
UserPromptSubmit hook  ──→  per-turn: 4 signals (context-pressure at 2 levels), single most-urgent alert
Stop hook             ──→  session-end: 6 failure patterns, recovery recipes
                            ↓
              hooks/lib/session-health-signals.sh  (shared signal library)
```

Both hooks are POSIX bash + jq only. They fail-open on infra errors (missing jq,
missing lib). The shared library is sourced, not executed.

## Per-turn signals (UserPromptSubmit hook)

Urgency order — exactly ONE alert fires per turn (single-alert bar):

| Priority | Signal | Threshold | Alert + recipe |
|----------|--------|-----------|----------------|
| 1 | **context STRONG** | ≥ 0.70 × effective window | "Context critically full — run `/catalyst:handoff reground` NOW" |
| 2 | **context WARN** | ≥ 0.50 × effective window | "Approaching effective context limit — run `/catalyst:handoff reground`" |
| 3 | **contradiction** | Last assistant turn contradicts a `Decision:` line in `.claude/PROJECT_STATE.md` | "Conflicts with decision '…'. Verify before proceeding." |
| 4 | **stale-read** | Edit on file F where last Read of F was >15 tool-use events ago | "Re-Read F before further edits to avoid old_string mismatch." |
| 5 | **repeated-tool** | Same tool call ×3 in last 5 turns | "Try a different approach (different command, different file, ask user)." |

### Recalibrated effective-window thresholds

The old `session-degradation-watch` v0.6 triggered at raw percentages of the
*advertised* window (warn at 60% = 120K tok for a 200K model). That was model-naïve.
Research shows the effective usable window is ≈70% of advertised before quality
degrades (8K–32K for frontier models per NoLiMa, even while claiming 128K+).

`session-health` v0.7 recalibrates to fractions of the *effective* window:

| Level | Old trigger | New trigger | At advertised=200K |
|-------|-------------|-------------|-------------------|
| WARN | 60% of advertised (120,000 tok) | 0.50 × effective | 70,000 tok |
| STRONG | 85% of advertised (170,000 tok) | 0.70 × effective | 98,000 tok |

Effective = advertised × `CATALYST_SH_EFFECTIVE_FRAC` (default 0.70). Alerts now
fire at 35% and 49% of the *advertised* window — much earlier than before, matching
where quality actually starts to slip.

## Session-end failure patterns (Stop hook)

Scans the full transcript once at session end. All 6 patterns from the OpenDev paper:

| Pattern | Signal | Recovery recipe |
|---------|--------|-----------------|
| `repeated-tool-call` | Same Bash/Read/Grep input ≥3× in last 5 turns | "Loop on '…'. Try different approach." |
| `edit-mismatch` | ≥2 `old_string not found` errors in last 5 turns | "Re-Read the file before next Edit." |
| `stale-read` | Edit on F where F was Written between last Read and this Edit | "Re-Read F — modified since last Read." |
| `recovery-spiral` | ≥3 consecutive re-Reads of previously-seen files | "Run `/catalyst:handoff reground` or `/clear` + handoff Resume." |
| `instruction-fade` | Same first 80 chars of user message repeated ≥2× in last 10 turns | "Re-state instruction in fresh session (handoff RECOVER)." |
| `context-drowning` | Any tool_result content >10KB | "For next big read, dispatch a subagent instead of inlining." |

All detections are appended to `.claude/session-health.log` with timestamp + session ID
+ pattern + recovery recipe.

## Suggest-only rule

This skill **suggests**; it never auto-recovers. Issue #60248 showed that in-loop
auto-recovery doesn't work — the hook fires in a context where the agent can't reliably
act on a recursive invocation. The recipe names the exact next step; acting on it is
the agent's choice.

The canonical degradation recovery is `/catalyst:handoff reground` — a WRITE mode that
checkpoints state into a typed JSON brief before the context wall hits. Alternatively,
`/catalyst:handoff split` forks a braided session into N self-contained briefs when the
session has accumulated multiple interleaved threads. Degradation alerts recommend one or
the other (suggest-only; which to use is the agent's choice).

## Composition with Tier-1 hooks

- **`UserPromptSubmit-orient.sh`** — injects repo orientation. The two hooks fire
  additively on UserPromptSubmit; Claude Code shows both context injections. Neither
  overwrites the other.
- **`Stop-commit-backstop.sh`** — flags uncommitted changes at session end. Both Stop
  hooks fire independently; neither's `additionalContext` overwrites the other.
- **`PreToolUse-verify-gate.sh`** — gate for evidence-first writes. Orthogonal;
  verify-gate denials are NOT counted as failure patterns.

## Configuration

**Per-turn hook config:** `.claude/session-health-watch.json`

```json
{
  "repeated_tool_call_count": 3,
  "repeated_tool_call_window_turns": 5,
  "stale_read_max_turns": 15,
  "check_contradiction_with_project_state": true,
  "log_path": ".claude/session-health.log"
}
```

**Session-end hook config:** `.claude/session-health.json`

```json
{
  "enabled_patterns": [
    "repeated-tool-call", "edit-mismatch", "stale-read",
    "recovery-spiral", "instruction-fade", "context-drowning"
  ],
  "thresholds": {
    "repeated_tool_call_count": 3,
    "repeated_tool_call_window_turns": 5,
    "stale_read_max_turns": 15,
    "edit_mismatch_count": 2,
    "recovery_spiral_count": 3
  },
  "log_path": ".claude/session-health.log"
}
```

Disable a noisy pattern by removing it from `enabled_patterns`. Log paths must stay
inside the project dir (enforced by the hook).

**Environment variables (override thresholds globally):**

| Variable | Default | Meaning |
|----------|---------|---------|
| `CATALYST_SH_ADVERTISED_TOKENS` | `200000` | Model's advertised context window in tokens |
| `CATALYST_SH_EFFECTIVE_FRAC` | `0.70` | Fraction of advertised window that is effective |
| `CATALYST_SH_WARN_FRAC` | `0.50` | Fraction of effective window for WARN alert |
| `CATALYST_SH_STRONG_FRAC` | `0.70` | Fraction of effective window for STRONG alert |
| `CATALYST_TIKTOKEN` | unset | Set to `1` to use tiktoken instead of chars÷4 heuristic |

## Commands

| Command | What it does |
|---------|-------------|
| `/session-health install` | Install both hooks (UserPromptSubmit + Stop) into `.claude/settings.json` |
| `/session-health uninstall` | Remove both hooks |
| `/session-health status` | Print last 20 entries from `.claude/session-health.log` |
| `/session-health patterns` | List all 6 named patterns with current enabled/disabled state |

## Bad / good example

**Bad — generic alert with no recipe:**
```
CONTEXT WARN: context is getting full. Be careful.
```
A generic alert gets ignored. "Be careful" is not a next step.

**Good — specific alert with exact recipe:**
```
CONTEXT WARN: transcript is ~76,525 tokens (effective window 140,000 tok;
warn threshold 70,000 tok). Approaching the effective context limit —
run /catalyst:handoff reground to checkpoint progress.
```
The agent can act on this immediately.

## When NOT to use

- **Short sessions** (<30 turns) — overhead doesn't pay back; hooks are inert but
  harmless.
- **CI / non-interactive runs** — UserPromptSubmit never fires; Stop fires but only
  the pattern log matters.
- **Projects where false positives would distract** — disable noisy patterns via
  `enabled_patterns` rather than uninstalling the whole skill.

## Model evolution

Assumes the model doesn't natively know when it's degrading. The effective-window
multiplier (0.70) reflects current frontier model behavior per NoLiMa/RULER (2025).
If future Claude models ship native context-budget warnings or reduce the positional-
bias effect substantially, the per-turn signal thresholds may be raised (less
aggressive) or the UserPromptSubmit hook may become vestigial. The session-end
pattern matchers depend only on transcript shape, not model capability — those are
more durable. Review annually or when a new flagship model lands with credible
long-context benchmark data.
