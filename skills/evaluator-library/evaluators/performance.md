### Axes

| Axis | What it measures |
|------|------------------|
| `algorithmic` | Are time / space complexities appropriate for input size? Are nested loops over large collections avoided? Are pathological cases addressed? |
| `allocation` | Are allocations bounded and short-lived where possible? Are large buffers reused? Are pathological GC pressure patterns avoided (strings concat in loops, etc.)? |
| `io` | Are I/O calls batched / cached where appropriate? Are network calls bounded by timeouts? Are file handles closed promptly? Scope: efficiency and bounding of I/O itself. |
| `blocking_calls` | In async / event-loop code, are CPU-bound work and lock acquisitions kept off the hot path? Is parallelism used where independence allows? Scope: thread/event-loop blocking — does NOT re-score I/O bounding (see `io`). |

### Score anchors (each axis 1-5)

- **5 — Exemplary.** Optimal complexity, measured. Benchmarks attached.
- **4 — Solid.** Reasonable choices, no obvious bottlenecks.
- **3 — Acceptable.** Works at current scale; specific issues to address before growth.
- **2 — Needs work.** Noticeable inefficiency at expected workload.
- **1 — Reject.** Pathological pattern (e.g., O(n²) over user-controlled input).

### Critique guidance

Score ≤3 must cite the file:line + the input size at which the problem manifests + the algorithmic fix. Speculation without data is acceptable only when input is user-controlled and unbounded.
