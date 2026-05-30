"""Dir-resolution correctness + bash/python parity."""
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("handoff_paths", ROOT / "scripts" / "handoff_paths.py")
hp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hp)


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.email", "t@e.st"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=path, check=True)
    (path / "f.txt").write_text("x")
    subprocess.run(["git", "add", "-A"], cwd=path, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=path, check=True)


class TestHandoffsDir(unittest.TestCase):
    def test_main_checkout(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            self.assertEqual(hp.handoffs_dir(repo).resolve(), (repo / ".claude" / "handoffs").resolve())

    def test_linked_worktree_centralizes_to_main(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            wt = Path(d) / "wt"
            subprocess.run(["git", "worktree", "add", "-q", str(wt), "-b", "feat"], cwd=repo, check=True)
            self.assertEqual(hp.handoffs_dir(wt).resolve(), (repo / ".claude" / "handoffs").resolve())

    def test_not_a_repo_falls_back(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            self.assertEqual(hp.handoffs_dir(p), p / ".claude" / "handoffs")

    def test_bash_python_parity(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            wt = Path(d) / "wt"
            subprocess.run(["git", "worktree", "add", "-q", str(wt), "-b", "feat2"], cwd=repo, check=True)
            for loc in (repo, wt):
                py = str(hp.handoffs_dir(loc))
                sh = subprocess.run(["bash", str(ROOT / "scripts" / "handoff-dir.sh"), str(loc)],
                                    capture_output=True, text=True, check=True).stdout.strip()
                self.assertEqual(Path(py).resolve(), Path(sh).resolve(), f"parity mismatch at {loc}")

    def test_load_schema(self):
        schema = hp.load_schema()
        self.assertIsInstance(schema, dict)
        self.assertIn("$schema", schema)
        self.assertEqual(schema["properties"]["schema_version"]["const"], "1")


if __name__ == "__main__":
    unittest.main()
