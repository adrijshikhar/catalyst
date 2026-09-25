"""Prepare one commit of drift inside an eval-run.py disposable workspace."""
import json
import subprocess
from pathlib import Path


def prepare():
    workspace = Path.cwd()
    if not (workspace / ".git-HEAD").is_file():
        raise SystemExit("Run only in a staged eval workspace with .git-HEAD")
    brief = workspace / ".catalyst/handoffs/catalyst-read-drift.json"
    obj = json.loads(brief.read_text())

    def git(*args):
        return subprocess.check_output(["git", *args], text=True).strip()

    # A second invocation must not add another commit and change the expected count.
    existing = subprocess.run(["git", "rev-parse", "--verify", "refs/tags/brief-base"],
                              capture_output=True, text=True)
    if existing.returncode == 0:
        if git("rev-list", "--count", "brief-base..HEAD") != "1":
            raise SystemExit("Unexpected fixture history; use a fresh eval workspace")
        return
    if git("log", "-1", "--format=%s") != "fixture":
        raise SystemExit("Expected the eval runner's initial fixture commit")

    base = git("rev-parse", "HEAD")
    obj["state"]["head_sha"] = base
    obj["state"]["branch"] = git("branch", "--show-current")
    obj["state"]["worktree"] = {
        "root": str(workspace.resolve()), "is_linked": False,
        "git_common_dir": git("rev-parse", "--path-format=absolute", "--git-common-dir"),
    }
    git("tag", "brief-base", base)
    git("-c", "user.name=eval", "-c", "user.email=eval@catalyst",
        "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "after brief")
    brief.write_text(json.dumps(obj, indent=2) + "\n")


if __name__ == "__main__":
    prepare()
