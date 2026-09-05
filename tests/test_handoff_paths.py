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
    def _initialize(self, path, *flags):
        return subprocess.run(
            ["python3", str(ROOT / "scripts/handoff_paths.py"), "--init", *flags, str(path)],
            capture_output=True, text=True)

    def test_write_initialization_preserves_ignore_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d); _init_repo(repo)
            ignore = repo / ".gitignore"
            ignore.write_bytes(b"# existing\nbuild/")
            for _ in range(2):
                result = self._initialize(repo, "--tasks")
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(ignore.read_bytes(), b"# existing\nbuild/\n.catalyst/\n")
            self.assertTrue((repo / ".catalyst/tasks").is_dir())
            self.assertFalse((repo / ".catalyst/handoffs").exists())
            check = subprocess.run(["git", "check-ignore", "-q", ".catalyst/tasks/task.md"], cwd=repo)
            self.assertEqual(check.returncode, 0)

    def test_linked_write_initializes_only_main_store_and_ignore(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            wt = Path(d) / "wt"
            subprocess.run(["git", "worktree", "add", "-q", str(wt), "-b", "isolated"], cwd=repo, check=True)
            result = self._initialize(wt)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((repo / ".catalyst/handoffs").is_dir())
            self.assertEqual((repo / ".gitignore").read_text(), ".catalyst/\n")
            self.assertFalse((wt / ".catalyst").exists())
            self.assertFalse((wt / ".gitignore").exists())

    def test_non_git_write_creates_store_without_ignore(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)
            result = self._initialize(path)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((path / ".catalyst/handoffs").is_dir())
            self.assertFalse((path / ".gitignore").exists())

    def test_read_only_resolution_does_not_initialize(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d); _init_repo(path)
            hp.handoffs_dir(path)
            self.assertFalse((path / ".catalyst").exists())
            self.assertFalse((path / ".gitignore").exists())

    def test_init_rejects_symlinked_state_or_ignore_without_writing(self):
        for target in (".catalyst", ".gitignore"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as d:
                repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
                outside = Path(d) / "outside"
                if target == ".catalyst":
                    outside.mkdir()
                else:
                    outside.write_text("preserve\n")
                (repo / target).symlink_to(outside)
                result = self._initialize(repo)
                self.assertNotEqual(result.returncode, 0)
                if target == ".catalyst":
                    self.assertEqual(list(outside.iterdir()), [])
                    self.assertFalse((repo / ".gitignore").exists())
                else:
                    self.assertEqual(outside.read_text(), "preserve\n")
                    self.assertFalse((repo / ".catalyst").exists())

    def test_concurrent_initialization_adds_one_ignore_rule(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d); _init_repo(repo)
            processes = [subprocess.Popen(
                ["python3", str(ROOT / "scripts/handoff_paths.py"), "--init", str(repo)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(4)]
            for process in processes:
                _, error = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 0, error)
            self.assertTrue((repo / ".gitignore").exists())
            self.assertEqual((repo / ".gitignore").read_text(), ".catalyst/\n")

    def test_main_checkout(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            self.assertEqual(hp.handoffs_dir(repo).resolve(), (repo / ".catalyst" / "handoffs").resolve())

    def test_linked_worktree_centralizes_to_main(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            wt = Path(d) / "wt"
            subprocess.run(["git", "worktree", "add", "-q", str(wt), "-b", "feat"], cwd=repo, check=True)
            self.assertEqual(hp.handoffs_dir(wt).resolve(), (repo / ".catalyst" / "handoffs").resolve())

    def test_not_a_repo_falls_back(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            self.assertEqual(hp.handoffs_dir(p), p / ".catalyst" / "handoffs")

    def test_bash_python_parity(self):
        """Both resolvers must agree on every resolution case. Four copies of
        this logic existed before v0.8; two were untested and drifted."""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            wt = Path(d) / "wt"
            subprocess.run(["git", "worktree", "add", "-q", str(wt), "-b", "feat2"],
                           cwd=repo, check=True)
            nogit = Path(d) / "nogit"; nogit.mkdir()
            sub = repo / "src"; sub.mkdir()
            for loc in (repo, wt, nogit, sub):
                py = str(hp.handoffs_dir(loc))
                sh = subprocess.run(
                    ["bash", str(ROOT / "scripts" / "handoff-dir.sh"), str(loc)],
                    capture_output=True, text=True, check=True).stdout.strip()
                self.assertEqual(Path(py).resolve(), Path(sh).resolve(),
                                 f"parity mismatch at {loc}")

    def test_subdir_of_repo_resolves_to_repo_root(self):
        """A relative --git-common-dir ('.git') must resolve against the repo,
        not the caller's cwd."""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"; repo.mkdir(); _init_repo(repo)
            sub = repo / "deep" / "nested"; sub.mkdir(parents=True)
            self.assertEqual(hp.handoffs_dir(sub).resolve(),
                             (repo / ".catalyst" / "handoffs").resolve())

    def test_load_schema(self):
        schema = hp.load_schema()
        self.assertIsInstance(schema, dict)
        self.assertIn("$schema", schema)
        self.assertEqual(schema["properties"]["schema_version"]["const"], "1")


if __name__ == "__main__":
    unittest.main()
