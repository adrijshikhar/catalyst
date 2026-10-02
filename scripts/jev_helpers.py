"""Helper functions for TypeSafe Jev payload preparation, budgeting, and parsing."""
from __future__ import annotations

import re
from typing import Any

MAX_DIFF_CHARS = 50000
MAX_CLAIM_CHARS = 2000
MAX_CLAIMS_COUNT = 16
MAX_EVIDENCE_TOTAL_CHARS = 200000
MAX_EVIDENCE_ITEMS = 16


def _truncate_text(text: str, max_len: int, suffix: str = "\n[truncated]") -> str:
    if len(text) <= max_len:
        return text
    cutoff = max_len - len(suffix)
    return text[:cutoff] + suffix


def prepare_task_gate(
    task_markdown: str,
    git_diff: str,
    evidence: str | list[dict[str, str]] | None = None,
    auto_accept: float = 0.8,
) -> dict[str, Any]:
    """Prepare payload for jev_gate tool from a task markdown file, git diff, and evidence."""
    # Split request from completion
    parts = re.split(r"(?m)^##\s+Completion\b", task_markdown, maxsplit=1)
    request_text = parts[0].strip()
    completion_text = parts[1].strip() if len(parts) > 1 else ""

    # Extract claims from completion
    claims: list[str] = []
    if completion_text:
        # Match markdown list items: "- [x] ...", "- ...", "* [x] ...", etc.
        for line in completion_text.splitlines():
            line_str = line.strip()
            m = re.match(r"^[-*]\s+(?:\[[ xX]\]\s+)?(.+)$", line_str)
            if m:
                claim_text = m.group(1).strip()
                if claim_text and not claim_text.startswith("#"):
                    claims.append(_truncate_text(claim_text, MAX_CLAIM_CHARS, ""))

    if not claims:
        # Fallback claim if no bullet points found
        claims = ["All acceptance criteria and workspace instructions in the task are completed."]

    claims = claims[:MAX_CLAIMS_COUNT]

    # Process and truncate diff
    safe_diff = _truncate_text(git_diff, MAX_DIFF_CHARS, "\n[diff truncated]")

    # Extract verification evidence from markdown if not provided
    extracted_evidence_text = ""
    if completion_text and "### Verification Evidence" in completion_text:
        ev_part = completion_text.split("### Verification Evidence", 1)[1]
        extracted_evidence_text = ev_part.strip()

    # Budget evidence items
    evidence_items: list[dict[str, str]] = []
    if isinstance(evidence, list):
        for idx, item in enumerate(evidence[:MAX_EVIDENCE_ITEMS]):
            item_id = item.get("id", f"evidence-{idx}")
            item_text = item.get("text", "")
            evidence_items.append({"id": str(item_id), "text": str(item_text)})
    elif isinstance(evidence, str) and evidence.strip():
        evidence_items.append({"id": "execution-evidence", "text": evidence.strip()})
    elif extracted_evidence_text:
        evidence_items.append({"id": "task-completion-evidence", "text": extracted_evidence_text})
    else:
        evidence_items.append({"id": "task-status", "text": completion_text or "No separate evidence provided."})

    # Ensure aggregate evidence character cap
    total_chars = sum(len(it["text"]) for it in evidence_items)
    if total_chars > MAX_EVIDENCE_TOTAL_CHARS:
        budget_per_item = MAX_EVIDENCE_TOTAL_CHARS // len(evidence_items)
        budgeted_items: list[dict[str, str]] = []
        for it in evidence_items:
            budgeted_items.append({
                "id": it["id"],
                "text": _truncate_text(it["text"], budget_per_item, "\n[evidence truncated]"),
            })
        evidence_items = budgeted_items

    return {
        "request": request_text,
        "diff": safe_diff,
        "claims": claims,
        "evidence": evidence_items,
        "auto_accept": auto_accept,
    }


def parse_gate_result(result: dict[str, Any]) -> dict[str, Any]:
    """Parse output from jev_gate tool."""
    action = str(result.get("action", "review"))
    review = result.get("review") if isinstance(result.get("review"), dict) else {}
    safe_to_apply = float(result.get("safe_to_apply") if "safe_to_apply" in result else review.get("safe_to_apply", 0.0))
    composite = float(result.get("composite") if "composite" in result else review.get("composite", 0.0))
    scores = result.get("scores") if isinstance(result.get("scores"), dict) else review.get("scores", {})

    verification = result.get("verification") if isinstance(result.get("verification"), dict) else {}
    claims = result.get("claims") or verification.get("results") or result.get("results") or []

    unresolved_claims: list[str] = []
    for c in claims:
        verdict = str(c.get("verdict", "")).lower()
        c_action = str(c.get("action", "")).lower()
        if verdict != "verified" or c_action not in ("auto", "verified"):
            unresolved_claims.append(str(c.get("claim", "")))

    is_accepted = (action == "auto" and not unresolved_claims)

    return {
        "action": action,
        "is_accepted": is_accepted,
        "safe_to_apply": safe_to_apply,
        "composite": composite,
        "scores": scores,
        "claims": claims,
        "unresolved_claims": unresolved_claims,
    }


def prepare_drift_verify(
    stored_sha: str,
    head_sha: str,
    decisions: list[str],
    next_acceptance_check: str,
    git_log: str,
    git_diff_stat: str,
    diff_excerpts: str = "",
) -> dict[str, Any]:
    """Prepare payload for jev_verify to check semantic commit drift during READ mode."""
    decisions_summary = "; ".join(decisions) if decisions else "None specified"
    claims = [
        f"Landed commits between {stored_sha} and {head_sha} do not conflict with locked decisions: {decisions_summary}",
        f"Landed commits between {stored_sha} and {head_sha} do not invalidate next acceptance check: {next_acceptance_check}",
    ]

    evidence_items = [
        {"id": "git-log", "text": _truncate_text(git_log, 30000)},
        {"id": "git-diff-stat", "text": _truncate_text(git_diff_stat, 30000)},
    ]
    if diff_excerpts:
        evidence_items.append({"id": "diff-excerpts", "text": _truncate_text(diff_excerpts, 120000)})

    return {
        "claims": claims,
        "evidence": evidence_items,
    }


def parse_drift_result(result: dict[str, Any]) -> dict[str, Any]:
    """Parse output from jev_verify for semantic commit drift."""
    claims = result.get("claims") or result.get("results") or []
    conflicts: list[str] = []

    for c in claims:
        verdict = str(c.get("verdict", "")).lower()
        action = str(c.get("action", "")).lower()
        claim_text = str(c.get("claim", ""))
        if verdict in ("contradicted", "unsupported") or action in ("escalate", "review"):
            conflicts.append(f"{claim_text} ({verdict}/{action})")

    is_clean = len(conflicts) == 0 and len(claims) > 0
    if is_clean:
        summary = "Jev: clean — no conflict with active task"
    elif conflicts:
        summary = f"Jev: semantic drift conflict detected ({len(conflicts)} unverified claim{'s' if len(conflicts) > 1 else ''})"
    else:
        summary = "Jev: drift verification inconclusive"

    return {
        "is_clean": is_clean,
        "conflicts": conflicts,
        "summary": summary,
        "claims": claims,
    }
