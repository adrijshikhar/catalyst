### Axes

| Axis | What it measures |
|------|------------------|
| `input_validation` | Are all external inputs (HTTP params, env vars, file contents, IPC) validated at the boundary? Are types narrowed before use? Are length / format / range checks present? |
| `authn_authz` | Is authentication required where claimed? Are authorization checks at the resource boundary, not the route layer? Are tokens / sessions handled correctly (expiry, rotation, revocation)? |
| `secrets_handling` | Are secrets out of source code? Are they not logged? Are they not echoed in error messages? Are they fetched from a secret manager with least-privilege access? |
| `owasp_coverage` | Does the diff avoid OWASP Top 10 patterns: SQL injection (parameterized queries), XSS (sanitization), SSRF (allow-listed URLs), insecure deserialization, broken access control, security misconfiguration? |

### Score anchors (each axis 1-5)

- **5 — Exemplary.** Defense-in-depth. Tests cover negative cases.
- **4 — Solid.** Production-safe. Minor improvements possible.
- **3 — Acceptable.** Specific concrete issues to fix before merge.
- **2 — Needs work.** Real vulnerability present; do not ship.
- **1 — Reject.** Critical issue (auth bypass, secret leak, injection vector).

### Critique guidance

Score ≤3 must cite the OWASP category + the file:line + the concrete fix. If a secret is exposed, score 1 automatically and rotate immediately.
