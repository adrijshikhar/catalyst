---
description: Show a compact read-only report of the current session — approximate token usage (exact when transcript usage is present), cache-read ratio, and recent session-degradation / failure-pattern alerts. No model call; numbers are computed by scripts/session-stats.sh.
---

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/session-stats.sh "$CLAUDE_TRANSCRIPT_PATH"` (use the current session's transcript path; if unavailable, run with no argument). Print the rendered report verbatim to the user. Do not recompute or editorialize the numbers — the script is the source of truth. This is a read-only diagnostic; it never modifies state.
