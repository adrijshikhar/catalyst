"""Unit tests for the deterministic validators added to scripts/lint.py."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"

# Load scripts/lint.py as a module (it has no package).
_spec = importlib.util.spec_from_file_location("catalyst_lint", ROOT / "scripts" / "lint.py")
lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint)


class TestInvisibleUnicode(unittest.TestCase):
    def test_flags_zero_width_space(self):
        errors: list[str] = []
        lint.scan_invisible_unicode(FIXTURES / "bad_unicode.md", errors)
        self.assertTrue(any("invisible" in e.lower() or "U+200B" in e for e in errors))

    def test_clean_text_passes(self):
        errors: list[str] = []
        lint.scan_invisible_unicode(ROOT / "README.md", errors)
        self.assertEqual(errors, [])


class TestBlockScalarGuard(unittest.TestCase):
    def test_flags_literal_block_scalar(self):
        errors: list[str] = []
        lint.check_description_scalar(FIXTURES / "bad_blockscalar.md", errors)
        self.assertTrue(any("block scalar" in e.lower() for e in errors))


class TestNoPersonalPaths(unittest.TestCase):
    def test_flags_users_path(self):
        errors: list[str] = []
        text = "see /Users/nemesis/Projects/foo for details"
        lint.scan_personal_paths_text("dummy.md", text, errors)
        self.assertTrue(any("personal path" in e.lower() for e in errors))

    def test_allowlisted_placeholder_passes(self):
        errors: list[str] = []
        text = "put it under /Users/you/project"
        lint.scan_personal_paths_text("dummy.md", text, errors)
        self.assertEqual(errors, [])


class TestSettingsHookSchema(unittest.TestCase):
    def test_legacy_shape_flagged(self):
        errors: list[str] = []
        data = {"hooks": {"Stop": [{"command": "bash x.sh"}]}}
        lint.validate_hook_settings_obj(data, "settings.json", errors)
        self.assertTrue(any("hooks" in e for e in errors))

    def test_valid_shape_passes(self):
        errors: list[str] = []
        data = {"hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "bash x.sh"}]}]}}
        lint.validate_hook_settings_obj(data, "settings.json", errors)
        self.assertEqual(errors, [])


class TestFileRefResolution(unittest.TestCase):
    def test_dead_ref_flagged(self):
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "see [x](./does-not-exist-xyz.md)", ROOT, errors)
        self.assertTrue(any("unresolved" in e.lower() for e in errors))

    def test_existing_ref_passes(self):
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "see [readme](./README.md)", ROOT, errors)
        self.assertEqual(errors, [])

    def test_bare_path_not_matched(self):
        # Bare paths (prose / code fences / JSON data) are intentionally ignored.
        errors: list[str] = []
        lint.check_file_refs_text("doc.md", "run ./nonexistent-bare.md now", ROOT, errors)
        self.assertEqual(errors, [])


class TestHooksJson(unittest.TestCase):
    """The declared hook file is how the plugin registers its hooks. A typo in an
    event name, a missing script, or a path that is not plugin-root-relative
    means a hook silently never fires — so lint rejects all three."""

    def _write(self, root, data):
        hooks = root / "hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        (root / "hooks.json").write_text(json.dumps(data), encoding="utf-8")
        return hooks

    def _valid(self, script_name="PreCompact-handoff-write.sh"):
        return {"hooks": {"PreCompact": [{"matcher": "", "hooks": [
            {"type": "command", "timeout": 10,
             "command": f'"${{CLAUDE_PLUGIN_ROOT}}/hooks/{script_name}"'}]}]}}

    def test_valid_declaration_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, self._valid())
            script = hooks / "PreCompact-handoff-write.sh"
            script.write_text("#!/usr/bin/env bash\n")
            script.chmod(0o755)
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertEqual(errors, [])

    def test_unknown_event_name_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, {"hooks": {"PreCompactt": [{"matcher": "", "hooks": [
                {"type": "command", "command": '"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"'}]}]}})
            # The referenced script must exist and be executable, so the
            # missing-script / non-executable branches stay silent and only
            # the unknown-event branch can produce an error here.
            script = hooks / "x.sh"
            script.write_text("#!/usr/bin/env bash\n")
            script.chmod(0o755)
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("unknown hook event" in e for e in errors), errors)
            self.assertTrue(any("PreCompactt" in e for e in errors), errors)

    def test_missing_script_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            self._write(root, self._valid("does-not-exist.sh"))
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("does-not-exist.sh" in e for e in errors), errors)

    def test_command_without_plugin_root_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, {"hooks": {"PreCompact": [{"matcher": "", "hooks": [
                {"type": "command", "command": "bash hooks/PreCompact-handoff-write.sh"}]}]}})
            (hooks / "PreCompact-handoff-write.sh").write_text("#!/usr/bin/env bash\n")
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("CLAUDE_PLUGIN_ROOT" in e for e in errors), errors)

    def test_sessionstart_source_list_rejected(self):
        """A SessionStart matcher enumerating sources silently drops the ones it
        omits. Only match-all forms are permitted."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, {"hooks": {"SessionStart": [
                {"matcher": "startup|clear|compact", "hooks": [
                    {"type": "command", "command": '"${CLAUDE_PLUGIN_ROOT}/hooks/s.sh"'}]}]}})
            (hooks / "s.sh").write_text("#!/usr/bin/env bash\n")
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("SessionStart" in e and "matcher" in e for e in errors), errors)

    def test_non_executable_script_rejected(self):
        """A script that exists but lacks the execute bit is the exact failure
        this check exists to prevent: Claude Code cannot run it, so the hook
        would never fire. Toggling the mode back to 0o755 must clear it."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, self._valid())
            script = hooks / "PreCompact-handoff-write.sh"
            script.write_text("#!/usr/bin/env bash\n")
            script.chmod(0o644)
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("not executable" in e for e in errors), errors)

            script.chmod(0o755)
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertEqual(errors, [])

    def test_command_with_trailing_argument_passes(self):
        """The relative path must be cut at the closing quote, not stripped
        from the end of the string — a command that passes an argument after
        the quoted path (the form superpowers ships) must still resolve."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            hooks = self._write(root, {"hooks": {"SessionStart": [{"matcher": "", "hooks": [
                {"type": "command",
                 "command": '"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" session-start'}]}]}})
            script = hooks / "run-hook.cmd"
            script.write_text("#!/usr/bin/env bash\n")
            script.chmod(0o755)
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertEqual(errors, [])

    def test_malformed_json_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "hooks.json").write_text("{not json", encoding="utf-8")
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("hooks.json" in e for e in errors), errors)

    def test_absent_file_is_not_an_error(self):
        """Not every plugin declares hooks; absence is valid."""
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_hooks_json(errors, root=Path(d), rel_path="hooks.json")
            self.assertEqual(errors, [])

    def _fallback_form(self, script_name):
        return {"hooks": {"PreCompact": [{"matcher": "", "hooks": [
            {"type": "command", "timeout": 10,
             "command": f'"${{PLUGIN_ROOT:-${{CLAUDE_PLUGIN_ROOT}}}}/hooks/{script_name}"'}]}]}}

    def _script(self, root, name, mode=0o755):
        hooks = root / "hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        s = hooks / name
        s.write_text("#!/usr/bin/env bash\n")
        s.chmod(mode)
        return s

    def test_fallback_command_form_resolves_script(self):
        """The cross-host form ${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/... must be
        parsed to the script path, so a missing script is still caught."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            self._write(root, self._fallback_form("PreCompact-handoff-write.sh"))
            self._script(root, "PreCompact-handoff-write.sh")
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertEqual(errors, [])

            self._write(root, self._fallback_form("does-not-exist.sh"))
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="hooks.json")
            self.assertTrue(any("missing script" in e for e in errors), errors)

    def test_error_labels_use_the_given_path(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            cop = root / "alt" / "hooks"
            cop.mkdir(parents=True)
            (cop / "hooks.json").write_text("{not json", encoding="utf-8")
            errors = []
            lint.check_hooks_json(errors, root=root, rel_path="alt/hooks/hooks.json")
            self.assertTrue(any(e.startswith("alt/hooks/hooks.json") for e in errors), errors)


class TestMarketplaceDescription(unittest.TestCase):
    def _root(self, d, pj_desc, mp_desc):
        root = Path(d)
        cp = root / ".claude-plugin"; cp.mkdir()
        (cp / "plugin.json").write_text(json.dumps({"name": "catalyst", "version": "0.9.0", "description": pj_desc}))
        (cp / "marketplace.json").write_text(json.dumps({"name": "catalyst", "owner": {"name": "x"},
            "plugins": [{"name": "catalyst", "source": "./", "description": mp_desc}]}))
        return root

    def test_description_drift_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._root(d, "A", "B")
            errors = []
            lint.check_marketplace_consistency(root, errors)
            self.assertTrue(any("description" in e for e in errors), errors)

    def test_identical_descriptions_pass(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._root(d, "A", "A")
            errors = []
            lint.check_marketplace_consistency(root, errors)
            self.assertEqual(errors, [])

    def test_real_tree_is_host_neutral(self):
        pj = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text())
        mp = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())
        for desc in (pj["description"], mp["plugins"][0]["description"]):
            self.assertNotIn("for Claude Code", desc)



class TestRootPluginManifest(unittest.TestCase):
    """Antigravity CLI reads a root plugin.json. It must never carry an Agent
    Plugins $schema: Codex would then drop every hook (openai/codex #37027)."""

    def _root(self, d, manifest, claude_version="0.1.0"):
        root = Path(d)
        if manifest is not None:
            (root / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        cp = root / ".claude-plugin"; cp.mkdir()
        (cp / "plugin.json").write_text(json.dumps({"name": "catalyst", "version": claude_version}), encoding="utf-8")
        return root

    def _valid(self):
        return {"name": "catalyst", "version": "0.1.0", "description": "d"}

    def test_valid_passes(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_root_plugin_manifest(errors, root=self._root(d, self._valid()))
            self.assertEqual(errors, [])

    def test_missing_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_root_plugin_manifest(errors, root=self._root(d, None))
            self.assertTrue(any("plugin.json: missing" in e for e in errors), errors)

    def test_schema_key_forbidden(self):
        with tempfile.TemporaryDirectory() as d:
            m = self._valid(); m["$schema"] = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
            errors = []
            lint.check_root_plugin_manifest(errors, root=self._root(d, m))
            self.assertTrue(any("37027" in e for e in errors), errors)

    def test_version_drift_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_root_plugin_manifest(errors, root=self._root(d, self._valid(), claude_version="0.1.1"))
            self.assertTrue(any("drift" in e for e in errors), errors)

    def test_real_tree_passes(self):
        errors = []
        lint.check_root_plugin_manifest(errors, root=ROOT)
        self.assertEqual(errors, [])


class TestLegacyHooksLocation(unittest.TestCase):
    """Antigravity CLI reads a ROOT hooks.json and never hooks/. If the file moves
    back under hooks/ while the manifest declares the root path, Antigravity loses
    the hooks silently — lint must catch it."""

    def _tree(self, d, declared, legacy_exists):
        root = Path(d)
        cp = root / ".claude-plugin"; cp.mkdir()
        (cp / "plugin.json").write_text(json.dumps({"name": "catalyst", "hooks": declared}), encoding="utf-8")
        if legacy_exists:
            (root / "hooks").mkdir(exist_ok=True)
            (root / "hooks" / "hooks.json").write_text("{}", encoding="utf-8")
        return root

    def test_legacy_file_with_root_declaration_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_no_legacy_hooks_location(errors, root=self._tree(d, "./hooks.json", True))
            self.assertTrue(any("Antigravity" in e for e in errors), errors)

    def test_no_legacy_file_passes(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []
            lint.check_no_legacy_hooks_location(errors, root=self._tree(d, "./hooks.json", False))
            self.assertEqual(errors, [])

    def test_declared_path_read_from_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(lint.declared_hooks_path(self._tree(d, "./hooks.json", False)), "hooks.json")

    def test_real_tree_passes(self):
        errors = []
        lint.check_no_legacy_hooks_location(errors, root=ROOT)
        self.assertEqual(errors, [])
        self.assertEqual(lint.declared_hooks_path(ROOT), "hooks.json")


class TestManifestVersions(unittest.TestCase):
    """Four manifests carry version; release.sh bumps all, lint proves they agree,
    and Codex's declared hooks path must match Claude's."""

    def _root(self, d, versions, codex_hooks="./hooks.json"):
        root = Path(d)
        (root / ".claude-plugin").mkdir(); (root / ".codex-plugin").mkdir()
        (root / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": "c", "version": versions[0], "hooks": "./hooks.json"}))
        (root / "plugin.json").write_text(json.dumps({"name": "c", "version": versions[1]}))
        (root / ".codex-plugin" / "plugin.json").write_text(json.dumps({"name": "c", "version": versions[2], "hooks": codex_hooks}))
        (root / "gemini-extension.json").write_text(json.dumps({"name": "c", "version": versions[3]}))
        return root

    def test_equal_passes(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []; lint.check_manifest_versions_equal(errors, root=self._root(d, ["1.0.0"] * 4)); self.assertEqual(errors, [])

    def test_drift_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []; lint.check_manifest_versions_equal(errors, root=self._root(d, ["1.0.0", "1.0.0", "1.0.1", "1.0.0"]))
            self.assertTrue(any("drift" in e and "1.0.1" in e for e in errors), errors)

    def test_codex_hooks_path_must_match_claude(self):
        with tempfile.TemporaryDirectory() as d:
            errors = []; lint.check_manifest_versions_equal(errors, root=self._root(d, ["1.0.0"] * 4, codex_hooks="./hooks/hooks.json"))
            self.assertTrue(any("differs" in e for e in errors), errors)

    def test_real_tree(self):
        errors = []; lint.check_manifest_versions_equal(errors, root=ROOT); self.assertEqual(errors, [])

if __name__ == "__main__":
    unittest.main()
