---
name: verify-handoff
description: Use when the user requests a Catalyst handoff with Jev verification, or Catalyst WRITE routes here because handoff.verification is set to jev. This separately installed integration checks checkpoint claims against evidence before saving; it requires Catalyst's handoff skill.
---

# Verify a Catalyst handoff

Check factual checkpoint claims against captured evidence using TypeSafe Jev.
Catalyst owns checkpoint construction, validation, storage, and the narrative.
This skill adds advisory verification to WRITE only.

Use only the user's own Jev MCP connection, authenticated with their own API
key in the host's MCP configuration or secret store. Catalyst supplies no key
or shared credential service. Never ask the user to paste a key into chat,
read or copy it into evidence, or store it in Catalyst config or artifacts.
Authentication failures follow the unavailable-verification path below.

1. **Entry:** when called from an active Catalyst WRITE, use its current draft
   and evidence, perform steps 2–5, and return revised claims, risks, and status.
   Do not start another WRITE or publish files. When invoked directly, load the
   installed Catalyst `handoff` skill (`catalyst:handoff` on namespaced hosts)
   and start one WRITE with verification explicitly requested. Mark this skill
   as already active for that draft: run steps 2–5 at WRITE's verification step
   without re-invoking either skill. With older Catalyst versions lacking that
   step, run it just before final validation/publication. Resolve helper paths
   from Catalyst's skill, never from this integration or the working directory.
   If Catalyst is unavailable, report that no checkpoint was written.
2. Select concrete factual claims from the draft's test results and change
   summary. Keep goals, planned acceptance checks, and user preferences separate
   from claims of completed work. Pair claims with actual captured command
   output, diffs, or relevant source excerpts from the same work state. The
   draft itself and another agent's completion assertion are not proof.
3. Discover the host's Jev `jev_verify` tool (often `mcp__jev__jev_verify`).
   Send one bounded request with `claims` and `evidence`, using its declared
   schema. Send only relevant excerpts, excluding credentials and unrelated
   private content. Respect the project's external-data restrictions; when
   evidence cannot be shared, skip Jev and record that limitation.
4. Interpret each result by both verdict and review status:

   | Result | Action before saving |
   |---|---|
   | `verified` with `auto` | Keep the claim at the scope supported by the evidence. |
   | `contradicted` or `unsupported`, including `auto` | Inspect evidence and correct, qualify, or remove the claim. |
   | `review`, missing result, or malformed response | Preserve uncertainty; do not label the claim verified. |

   `auto` means confidence in the verdict, not that the claim is true.
   Jev does not run tests, prove correctness, or authorize actions. Corrections
   made after the call are agent revisions, not newly Jev-verified claims.
5. If Jev is absent, errors, or times out, continue Catalyst WRITE and record
   `Jev verification not performed: <reason>` in `state.open_risks`. Do not
   install tools, change host configuration, or retry in a loop. If there are
   no factual claims or no usable evidence, skip the call and state why. Keep
   unresolved claims and partial coverage in `state.open_risks`, alongside
   existing risks; do not add schema fields or a separate report file.
6. Validate the final revised brief with Catalyst's validator, then let its
   WRITE workflow publish the checkpoint and prepend the narrative using the
   same qualified claims. Preserve every existing storage and error check.
   Add one concise verification-status line to the confirmation, naming any
   skipped or unresolved coverage. Keep Catalyst's resume prompt last.

**Example:** A draft says “all tests passed,” but the captured output covers
only renderer tests. Save “renderer tests passed” and record that the remaining
suite was not run. Do not call the whole checkpoint verified.
