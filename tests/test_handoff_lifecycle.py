"""Brief inventory + orphan pruning."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


hl = _load("handoff_list", "scripts/handoff-list.py")
hpr = _load("handoff_prune", "scripts/handoff-prune.py")


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.email", "t@e.st"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=path, check=True)
    (path / "f.txt").write_text("x")
    subprocess.run(["git", "add", "-A"], cwd=path, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=path, check=True)


def _brief(store: Path, key: str, branch: str, age_days: int = 0) -> Path:
    ts = (datetime.now(timezone.utc) - timedelta(days=age_days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    store.mkdir(parents=True, exist_ok=True)
    p = store / f"{key}.json"
    p.write_text(json.dumps({
        "schema_version": "1", "key": key, "timestamp": ts, "mode": "WRITE",
        "resume": {"done_when": "d", "resume_by": "r"},
        "state": {"branch": branch, "next_acceptance_check": "c",
                  "worktree": {"root": str(store.parent.parent), "is_linked": False,
                               "git_common_dir": str(store.parent.parent / ".git")}},
    }), encoding="utf-8")
    return p


class TestList(unittest.TestCase):
    def test_canonical_inventory_surfaces_both_stores_without_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d); _init_repo(repo)
            store = hl._hp.handoffs_dir(repo)
            old = _brief(repo / ".claude/handoffs", "task", "feat/task")
            new = _brief(store, "task", "feat/task")
            before = {p: p.read_bytes() for p in (old, new)}
            rows = hl.collect(store, repo)
            self.assertEqual({Path(row["path"]).resolve() for row in rows},
                             {old.resolve(), new.resolve()})
            output = hl.render(rows)
            self.assertIn(".catalyst/handoffs/task.json", output)
            self.assertIn(".claude/handoffs/task.json", output)
            self.assertEqual(before, {p: p.read_bytes() for p in (old, new)})
            self.assertFalse((repo / ".gitignore").exists())

    def test_reports_branch_liveness_and_current(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            cur = subprocess.run(["git", "branch", "--show-current"], cwd=repo,
                                 capture_output=True, text=True).stdout.strip()
            store = repo / ".claude" / "handoffs"
            _brief(store, cur, cur)
            _brief(store, "feat-gone", "feat/gone")
            rows = {r["key"]: r for r in hl.collect(store, repo)}
            self.assertTrue(rows[cur]["branch_exists"])
            self.assertTrue(rows[cur]["is_current"])
            self.assertFalse(rows["feat-gone"]["branch_exists"])
            self.assertFalse(rows["feat-gone"]["is_current"])

    def test_flags_the_legacy_slot(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            _brief(store, "HANDOFF", "")
            rows = {r["key"]: r for r in hl.collect(store, repo)}
            self.assertTrue(rows["HANDOFF"]["legacy"])

    def test_unreadable_brief_does_not_crash_the_listing(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"; store.mkdir(parents=True)
            (store / "broken.json").write_text("{not json", encoding="utf-8")
            rows = hl.collect(store, repo)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["branch"], "")


class TestPrune(unittest.TestCase):
    def test_old_orphan_is_a_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            _brief(store, "feat-gone", "feat/gone", age_days=90)
            keys = [c["key"] for c in hpr.candidates(store, repo)]
            self.assertEqual(keys, ["feat-gone"])

    def test_recent_orphan_is_not_a_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            _brief(store, "feat-new", "feat/new", age_days=2)
            self.assertEqual(hpr.candidates(store, repo), [])

    def test_current_branch_brief_is_never_a_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            cur = subprocess.run(["git", "branch", "--show-current"], cwd=repo,
                                 capture_output=True, text=True).stdout.strip()
            store = repo / ".claude" / "handoffs"
            _brief(store, cur, cur, age_days=400)
            self.assertEqual(hpr.candidates(store, repo), [])

    def test_legacy_slot_is_never_a_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            _brief(store, "HANDOFF", "feat/gone", age_days=400)
            self.assertEqual(hpr.candidates(store, repo), [])

    def test_dry_run_deletes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            p = _brief(store, "feat-gone", "feat/gone", age_days=90)
            hpr.prune(store, repo, apply=False)
            self.assertTrue(p.exists(), "dry run must not delete")

    def test_apply_deletes_only_candidates(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            cur = subprocess.run(["git", "branch", "--show-current"], cwd=repo,
                                 capture_output=True, text=True).stdout.strip()
            store = repo / ".claude" / "handoffs"
            gone = _brief(store, "feat-gone", "feat/gone", age_days=90)
            keep = _brief(store, cur, cur, age_days=90)
            hpr.prune(store, repo, apply=True)
            self.assertFalse(gone.exists())
            self.assertTrue(keep.exists())

    def test_age_prefers_brief_timestamp_over_mtime(self):
        """A brief copied between machines gets a fresh mtime; the in-file
        timestamp is the durable signal."""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            store = repo / ".claude" / "handoffs"
            p = _brief(store, "feat-gone", "feat/gone", age_days=400)
            p.touch()  # mtime = now, timestamp still 400 days old
            self.assertEqual([c["key"] for c in hpr.candidates(store, repo)],
                             ["feat-gone"])

    def test_is_current_guard_holds_on_unborn_head(self):
        """Isolates the is_current guard from branch_exists.

        In every other fixture, being on a branch implies that branch shows up
        in `git branch --list`, so branch_exists alone would already protect
        it — is_current never gets exercised on its own. An unborn HEAD (repo
        initialized, nothing committed) breaks that overlap: `git branch
        --show-current` reports the future branch name while `git branch
        --list` reports nothing, so is_current is True and branch_exists is
        False. That is the one state that proves the guard does something.
        """
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "t@e.st"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)
            cur = subprocess.run(["git", "branch", "--show-current"], cwd=repo,
                                 capture_output=True, text=True).stdout.strip()
            store = repo / ".claude" / "handoffs"
            _brief(store, cur, cur, age_days=400)
            self.assertEqual(hpr.candidates(store, repo), [])


if __name__ == "__main__":
    unittest.main()
