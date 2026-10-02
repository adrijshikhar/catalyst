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
    """Prepare payload for jev_verify to check semantic commit drift during READ mode.

    jev_verify does not impose artificial item or character limits in its schema.
    Emits granular claims per decision to avoid monolithic false-unsupported verdicts.
    """
    claims = []
    if decisions:
        for d in decisions:
            claims.append(
                f"Landed commits between {stored_sha} and {head_sha} do not conflict with locked decision: {d}"
            )
    else:
        claims.append(
            f"Landed commits between {stored_sha} and {head_sha} do not conflict with locked decisions: None specified"
        )

    claims.append(
        f"Landed commits between {stored_sha} and {head_sha} do not invalidate next acceptance check: {next_acceptance_check}"
    )

    evidence_items = [
        {"id": "git-log", "text": git_log},
        {"id": "git-diff-stat", "text": git_diff_stat},
    ]
    if diff_excerpts:
        evidence_items.append({"id": "diff-excerpts", "text": diff_excerpts})

    return {
        "claims": claims,
        "evidence": evidence_items,
    }


def parse_drift_result(result: dict[str, Any]) -> dict[str, Any]:
    """Parse output from jev_verify for semantic commit drift.

    Distinguishes actual contradictions (drift conflicts) from unmentioned/unsupported
    decisions where commits simply did not touch that domain.
    """
    claims = result.get("claims") or result.get("results") or []
    conflicts: list[str] = []
    unverified: list[str] = []
    verified: list[str] = []

    for c in claims:
        verdict = str(c.get("verdict", "")).lower()
        action = str(c.get("action", "")).lower()
        claim_text = str(c.get("claim", ""))
        probs = c.get("probabilities") if isinstance(c.get("probabilities"), dict) else {}
        contradicts_prob = float(probs.get("contradicts", 0.0))

        if verdict == "contradicted" or action == "escalate" or contradicts_prob >= 0.5:
            conflicts.append(f"{claim_text} ({verdict}/{action})")
        elif verdict == "verified" and action in ("auto", "verified"):
            verified.append(claim_text)
        else:
            unverified.append(f"{claim_text} ({verdict}/{action})")

    is_clean = len(conflicts) == 0 and len(claims) > 0
    if conflicts:
        summary = f"Jev: semantic drift conflict detected ({len(conflicts)} conflict{'s' if len(conflicts) > 1 else ''})"
    elif is_clean and unverified:
        summary = f"Jev: clean ({len(verified)} verified, {len(unverified)} unmentioned/unverified)"
    elif is_clean and not unverified:
        summary = "Jev: clean — all decisions and acceptance checks verified"
    else:
        summary = "Jev: drift verification inconclusive"

    return {
        "is_clean": is_clean,
        "conflicts": conflicts,
        "unverified": unverified,
        "verified": verified,
        "summary": summary,
        "claims": claims,
    }


def format_gate_markdown(parsed: dict[str, Any]) -> str:
    """Format parsed gate result as a GitHub-ready markdown card."""
    action = str(parsed.get("action", "review")).upper()
    safe_to_apply = float(parsed.get("safe_to_apply", 0.0))
    composite = float(parsed.get("composite", 0.0))
    scores = parsed.get("scores", {})
    unresolved = parsed.get("unresolved_claims", [])

    badge = "🟢 AUTO" if action == "AUTO" else ("🟡 REVIEW" if action == "REVIEW" else "🔴 ESCALATE")

    lines = [
        f"### {badge} — Jev Task Gate (Safe to Apply: {safe_to_apply * 100:.0f}%, Composite: {composite:.2f})",
        "",
        "| Rubric | Score (0-2) | Status |",
        "| :--- | :--- | :--- |",
    ]

    rubric_names = [
        ("spec_match", "Spec Match"),
        ("correctness", "Correctness"),
        ("test_gap", "Test Gap"),
        ("blast_radius", "Blast Radius"),
    ]
    for key, label in rubric_names:
        val = scores.get(key)
        if isinstance(val, dict):
            s_val = float(val.get("score", 0.0))
        elif isinstance(val, (int, float)):
            s_val = float(val)
        else:
            s_val = 0.0

        if key in ("spec_match", "correctness"):
            status = "✅ Pass" if s_val >= 1.5 else ("⚠️ Review" if s_val >= 0.8 else "❌ Low")
        else:
            status = "✅ Low" if s_val <= 1.0 else "⚠️ High gap/risk"

        lines.append(f"| **{label}** | {s_val:.2f} / 2.0 | {status} |")

    lines.append("")
    if unresolved:
        lines.append("**Unresolved / Unsupported Claims:**")
        for u in unresolved:
            lines.append(f"- ⚠️ *{u}*")
    else:
        lines.append("**All claims verified against evidence.**")

    return "\n".join(lines) + "\n"
