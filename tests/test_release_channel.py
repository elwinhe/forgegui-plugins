import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "release_channel", Path(__file__).resolve().parents[1] / "release/release_channel.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class PackageBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.original = release.PLUGIN
        self.addCleanup(setattr, release, "PLUGIN", self.original)
        self.root = Path(self.temp.name)
        release.PLUGIN = self.root / "plugin"
        release.PLUGIN.mkdir()

    def test_internal_link_passes(self):
        (release.PLUGIN / "guide.md").write_text("Guide")
        (release.PLUGIN / "README.md").write_text("[Guide](guide.md)")
        self.assertEqual(release.package_problems(), [])

    def test_sibling_prefix_link_fails(self):
        sibling = self.root / "plugin-external"
        sibling.mkdir()
        (sibling / "secret.md").write_text("fixture")
        (release.PLUGIN / "README.md").write_text("[Outside](../plugin-external/secret.md)")
        self.assertTrue(any("escapes" in p for p in release.package_problems()))

    def test_external_and_dangling_symlinks_fail(self):
        (self.root / "outside.md").write_text("fixture")
        for target in (self.root / "outside.md", self.root / "missing"):
            with self.subTest(target=target):
                link = release.PLUGIN / "linked.md"
                link.symlink_to(target)
                self.assertTrue(any("symlink" in p for p in release.package_problems()))
                link.unlink()

    def test_symlink_directory_fails(self):
        (release.PLUGIN / "linked").symlink_to(self.root, target_is_directory=True)
        self.assertTrue(any("symlink" in p for p in release.package_problems()))

    def test_reference_link_boundaries(self):
        (release.PLUGIN / "guide.md").write_text("Guide")
        for href, expected in (("guide.md", []), ("missing.md", "broken link"),
                               ("../outside.md", "escapes")):
            with self.subTest(href=href):
                (release.PLUGIN / "README.md").write_text(f"[Guide][guide]\n\n[guide]: <{href}>\n")
                problems = release.package_problems()
                if expected:
                    self.assertTrue(any(expected in p for p in problems))
                else:
                    self.assertEqual(problems, [])


class VersionHeaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        for name in ("ROOT", "PLUGIN", "PLUGIN_JSON", "MCP_JSON", "MARKETPLACE_JSON", "CONFIG"):
            self.addCleanup(setattr, release, name, getattr(release, name))
        for source in (release.PLUGIN_JSON, release.MCP_JSON, release.MARKETPLACE_JSON,
                       release.ROOT / "release/channels.json"):
            target = root / source.relative_to(release.ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source.read_text())
        release.ROOT = root
        release.PLUGIN = root / release.CONFIG["plugin_dir"]
        release.PLUGIN_JSON = release.PLUGIN / ".claude-plugin/plugin.json"
        release.MCP_JSON = release.PLUGIN / ".mcp.json"
        release.MARKETPLACE_JSON = root / ".claude-plugin/marketplace.json"
        release.CONFIG = json.loads((root / "release/channels.json").read_text())

    def server(self):
        return release.load(release.MCP_JSON)["mcpServers"][release.CONFIG["mcp_server"]]

    def test_set_writes_version_header_beside_the_key(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(release.set_channel("production", "9.8.7"), 0)
        headers = self.server()["headers"]
        self.assertEqual(headers[release.VERSION_HEADER], "9.8.7")
        self.assertEqual(headers["Authorization"], "Bearer ${user_config.forgegui_api_key}")
        self.assertEqual(release.channel_problems(), [])

    def test_missing_or_stale_header_fails_check(self):
        for value in (None, "0.0.1"):
            with self.subTest(value=value):
                mcp = release.load(release.MCP_JSON)
                headers = mcp["mcpServers"][release.CONFIG["mcp_server"]]["headers"]
                headers.pop(release.VERSION_HEADER, None)
                if value:
                    headers[release.VERSION_HEADER] = value
                release.MCP_JSON.write_text(json.dumps(mcp))
                self.assertTrue(any(release.VERSION_HEADER in p for p in release.channel_problems()))


if __name__ == "__main__":
    unittest.main()
