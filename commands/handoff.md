---
description: Invoke the handoff skill. With no argument, runs WRITE mode and resolves the key via the 3-tier ladder (explicit name → current branch → legacy). With "$ARGUMENT" provided, uses it as the explicit tier-1 key. Special keywords — "read" / "resume" → READ mode; "recover" / "rebuild" → RECOVER mode.
---

Invoke the `handoff` skill.

If the user passed a single recognized keyword as `$ARGUMENT`, route to that mode:

- `read` or `resume` → READ mode (load existing brief for current branch / key)
- `recover` or `rebuild` → RECOVER mode (rebuild a degraded brief)
- any other non-empty value → WRITE mode with `$ARGUMENT` as the tier-1 explicit key (writes to `.claude/handoffs/<argument>.md`)
- empty argument → WRITE mode, resolve key via the ladder (branch → legacy)

Then follow the skill's procedure for the selected mode exactly. Confirm to the user which mode + which key was used.
