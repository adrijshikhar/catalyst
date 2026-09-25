"""Prepare a Jev verification request from one captured handoff eval run.

Prints JSON only; never connects to Jev or reads credentials. Review the evidence
before sending it through your own configured MCP connection.
"""
import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]


def prepare(snapshot_dir, scenario, run_number):
    snapshot_dir = Path(snapshot_dir).resolve()
    snapshot = json.loads((snapshot_dir / "results.json").read_text())
    entry = snapshot["evals"][str(scenario["id"])]
    run = next(r for r in entry["runs"] if r["run"] == run_number)
    transcript_path = (snapshot_dir / run["transcript_file"]).resolve()
    transcript_path.relative_to(snapshot_dir)
    transcript = []
    for line in transcript_path.read_text().splitlines():
        if not line.strip():
            continue
        event = json.loads(line)
        kind = event.get("type")
        if kind in ("assistant", "user"):
            blocks = event.get("message", {}).get("content", [])
            allowed = {"text", "tool_use"} if kind == "assistant" else {"tool_result"}
            kept = [b for b in blocks if isinstance(b, dict) and b.get("type") in allowed]
            if kept:
                transcript.append({"type": kind, "message": {"content": kept}})
        elif kind == "result":
            transcript.append({k: event[k] for k in ("type", "subtype", "is_error", "result")
                               if k in event})
    evidence = {"scenario": scenario["prompt"], "run": run_number,
                "snapshot_metadata": snapshot["meta"],
                "captured_files": run.get("files", {}), "transcript": transcript}
    label = f"Eval {scenario['id']}, run {run_number}"
    return {
        "claims": [f"{label}: {assertion}" for assertion in scenario["assertions"]],
        "evidence": [{"id": label, "text": json.dumps(evidence, ensure_ascii=False)}],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval", type=int, required=True)
    parser.add_argument("--run", type=int, default=0)
    parser.add_argument("--snapshots", type=Path,
                        default=ROOT / "skills/handoff/evals/snapshots")
    args = parser.parse_args()
    try:
        spec = json.loads((ROOT / "skills/handoff/evals/evals.json").read_text())
        scenario = next(e for e in spec["evals"] if e["id"] == args.eval)
        print(json.dumps(prepare(args.snapshots, scenario, args.run), ensure_ascii=False))
    except (OSError, ValueError, KeyError, StopIteration) as exc:
        parser.exit(1, f"Cannot prepare eval evidence: {exc or 'eval/run not found'}\n")
