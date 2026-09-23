import importlib.util
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


if __name__ == "__main__":
    unittest.main()
