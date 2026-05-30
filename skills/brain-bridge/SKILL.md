---
name: brain-bridge
description: Use when constructing a handoff PIPELINE BRIEF for a subagent and the project has a Company Brain MCP server (gbrain / brAIn / codebase-memory-mcp) configured. Injects file:line + decision-ID + convention-tag POINTERS into the brief (never inlined content — anti-bleed preserved). Trigger phrases — "/brain-bridge", "query the brain", "pull brain context", "ADR lookup", "gbrain", "brain MCP", "company brain". Use this skill liberally whenever a BRIEF would benefit from prior project knowledge that lives outside the working transcript.
---

# brain-bridge

Catalyst's connective tissue between the YC RFS "Company Brain" category (gbrain, brAIn, codebase-memory-mcp, etc.) and `handoff` PIPELINE mode. Brains store project knowledge as MCP-queryable documents; brain-bridge pulls relevant pointers into a BRIEF without flooding the orchestrator's context.

## The pointer contract

Brain results enter a BRIEF as **pointers**, NEVER as inlined content. A pointer is:

- File pointer: `path:line-range` plus relevance score
- Decision pointer: ADR ID + date + title
- Convention pointer: tag + doc anchor

The subagent reads the pointer and decides whether to fetch the file/decision/doc. This preserves the anti-bleed property of the BRIEF schema.

## Bundled adapters

Backend is selected by explicit `backend` field in `.claude/brain-bridge.json` (no auto-detection — security boundary).

| Backend ID | Adapter | Native shape consumed (raw stdin) |
|------------|---------|-----------------------------------|
| `gbrain` | `adapters/gbrain.sh` | `{pages: [{path, line_start, line_end, score, title}]}` |
| `brain` | `adapters/brain.sh` | `{sections: [{document_id, date?, title, tag?, path?, relevance}]}` |
| `codebase-memory-mcp` | `adapters/codebase-memory-mcp.sh` | `{symbols: [{name, file, line, kind, score}]}` |

Each adapter is a POSIX bash + jq script reading raw backend output on stdin and printing normalized JSON to stdout.

## Normalized pointer shape

```json
{
  "query": "auth flow",
  "results": [
    {"type": "file", "path": "src/auth/middleware.ts", "lines": "42-78", "relevance": 0.91},
    {"type": "decision", "id": "ADR-007", "date": "2026-03-15", "title": "JWT library choice", "relevance": 0.88},
    {"type": "convention", "tag": "error-handling", "doc": "docs/conventions.md#errors", "relevance": 0.65},
    {"type": "symbol", "name": "verifyJwt", "file": "src/auth/middleware.ts", "line": 42, "kind": "function", "relevance": 0.95}
  ],
  "token_budget_remaining": 1500
}
```

Type-specific fields per the table above. All results have a `relevance` score (0.0–1.0). Higher = more relevant.

## How it composes with handoff PIPELINE mode

During PIPELINE mode's BRIEF construction (step 5 of the protocol), the orchestrator MAY call brain-bridge BEFORE rendering. If brain-bridge returns pointers, they are inserted as a new section `## Brain pointers` between `## Files to read first` and `## Files to NOT load by default`.

Example:

```markdown
## Files to read first
- src/auth/middleware.ts — main auth flow
- tests/auth.test.ts — existing test patterns

## Brain pointers
- src/auth/middleware.ts:42-78 — JWT verify call sites (relevance 0.91)
- ADR-007 — JWT library choice (2026-03-15)
- docs/conventions.md#errors — project error-handling convention

## Files to NOT load by default
- generated/ — codegen output
```

The subagent treats Brain pointers as "skim if relevant" — they're not the primary task surface, just background context.

## Configuration

`.claude/brain-bridge.json`:

```json
{
  "backend": "gbrain",
  "endpoint": "stdio:gbrain",
  "query_token_budget": 2000,
  "max_pointers_per_brief": 6,
  "auto_query_in_pipeline_brief": true,
  "relevance_threshold": 0.5
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `backend` | (required) | One of `gbrain`, `brain`, `codebase-memory-mcp` |
| `endpoint` | (required) | MCP endpoint or CLI path |
| `query_token_budget` | 2000 | Max approx-tokens spent on Brain pointers per BRIEF |
| `max_pointers_per_brief` | 6 | Hard cap on pointer count |
| `auto_query_in_pipeline_brief` | true | If true, PIPELINE mode auto-queries during BRIEF construction |
| `relevance_threshold` | 0.5 | Pointers below this score are dropped |

## Commands

| Command | What it does |
|---------|-------------|
| `/brain-bridge query "<phrase>"` | Manual query — prints pointers to stdout for inspection |
| `/brain-bridge configure <backend>` | Interactive setup — writes `.claude/brain-bridge.json` |
| `/brain-bridge status` | Show configured backend + last 10 query log entries |

## When NOT to use

- **No Brain backend configured.** brain-bridge is opt-in; without a backend it returns empty results and the BRIEF renders without `## Brain pointers`. No-op is correct.
- **Subagent's task is contained in the current file set.** Brain pointers shine when context lives outside the working transcript; for tightly-scoped edits, skip.
- **One-off PIPELINE invocations** where the cost of an MCP round-trip outweighs the savings of better BRIEF context.

## Anti-patterns

- **Inlining brain content into the BRIEF.** Hard ban. Pointers only. Defeats anti-bleed and bloats the subagent's initial context.
- **Querying without a relevance threshold.** Low-relevance pointers crowd out the high-value ones and waste the token budget.
- **Configuring multiple backends in one session.** v0.6 ships single-backend per project. Multi-backend is Tier 4+ territory.
- **Treating brain pointers as load-bearing.** The brain is advisory context — never the primary source of truth. The BRIEF's `## Files to read first` remains the authoritative pointer list.

## Composition with other Catalyst skills

- `handoff` PIPELINE mode is the consumer — brain-bridge plugs into step 5 of the protocol.
- `evaluator-library` is unaffected — evaluators score the artifact, brain context is for generators.
- `session-health` is unaffected — brain pointers are part of the BRIEF, not the running transcript.

## Model evolution

Assumes the Brain ecosystem stays MCP-first. May need adapter additions if a non-MCP standard emerges (e.g., HTTP-only brain servers, native Claude Code memory integrations). Review annually per Catalyst convention.
