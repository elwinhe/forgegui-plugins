"""Offline packaging and guidance regressions; no live host/agent acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package", ROOT / "release/openai_package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class OpenAIPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / package.NAME
        self.files = package.expected_files()

    def test_repeated_and_independent_builds_identical(self):
        package.build(self.output, self.files)
        package.build(self.output, self.files)
        other = Path(self.temp.name) / "second" / package.NAME
        package.build(other, package.expected_files())
        self.assertEqual({p.relative_to(self.output): p.read_bytes() for p in self.output.rglob('*') if p.is_file()},
                         {p.relative_to(other): p.read_bytes() for p in other.rglob('*') if p.is_file()})

    def test_shared_source_is_byte_exact(self):
        provenance = json.loads(self.files['provenance.json'])
        for relative in provenance['sha256']:
            destination = 'WORKFLOW.md' if relative == 'SKILL.md' else relative
            self.assertEqual(self.files[f'skills/{package.NAME}/{destination}'],
                             (ROOT / package.SOURCE / relative).read_bytes())

    def test_drift_extra_cache_and_symlink_rejected(self):
        package.build(self.output, self.files)
        manifest = self.output / 'plugin.json'
        manifest.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'content drift'):
            package.check(self.output, self.files)
        with self.assertRaises(ValueError):
            package.build(self.output, self.files)
        manifest.write_bytes(self.files['plugin.json'])
        extra = self.output / '__pycache__'
        extra.mkdir()
        with self.assertRaisesRegex(ValueError, 'unexpected package directory'):
            package.check(self.output, self.files)
        extra.rmdir()
        manifest.unlink()
        manifest.symlink_to(ROOT / 'README.md')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            package.check(self.output, self.files)

    def test_source_drift_detected(self):
        package.build(self.output, self.files)
        changed = dict(self.files)
        changed[f'skills/{package.NAME}/WORKFLOW.md'] += b'\nsource update\n'
        with self.assertRaisesRegex(ValueError, 'content drift'):
            package.check(self.output, changed)

    def test_paths_rejected(self):
        for relative in ('../escape', '/absolute', 'references/../../escape', 'a\\b'):
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                package.safe_path(self.output, relative)
        with self.assertRaises(ValueError):
            package.output_path(ROOT / 'plugins' / package.NAME)
        with self.assertRaises(ValueError):
            package.output_path(self.output.parent)
        self.output.symlink_to(ROOT, target_is_directory=True)
        with self.assertRaises(ValueError):
            package.output_path(self.output)

    def test_unavailable_channels_and_submission(self):
        for channel, mode in [('production', 'preview'), ('missing', 'preview'), ('staging-beta', 'submission')]:
            with self.subTest(channel=channel, mode=mode), self.assertRaises(ValueError):
                package.expected_files(channel=channel, mode=mode)

    def test_reject_config_credentials_http_and_production_staging(self):
        config = json.loads((ROOT / 'release/channels.json').read_text())
        for url in ('http://example.com/mcp', 'https://key@example.com/mcp',
                    'https://example.com/mcp?key=secret', 'https://example.com/mcp#secret'):
            invalid = copy.deepcopy(config)
            invalid['channels']['staging-beta']['mcp_url'] = url
            with patch.object(package.json, 'loads', return_value=invalid), self.assertRaises(ValueError):
                package.channel_config(ROOT, None, 'preview')
        config['channels']['production'].update(available=True,
            mcp_url=config['channels']['staging-beta']['mcp_url'])
        with patch.object(package.json, 'loads', return_value=config), self.assertRaisesRegex(ValueError, 'staging'):
            package.channel_config(ROOT, 'production', 'preview')
        config['channels']['production']['mcp_url'] = 'https://example.com/mcp'
        with patch.object(package.json, 'loads', return_value=config), self.assertRaisesRegex(ValueError, 'OAuth'):
            package.channel_config(ROOT, 'production', 'preview')

    def test_manifests_and_remote_transport(self):
        portable = json.loads(self.files['plugin.json'])
        legacy = json.loads(self.files['.codex-plugin/plugin.json'])
        self.assertEqual(portable['name'], package.NAME)
        self.assertEqual(portable['extensions']['com.openai']['interface'], legacy['interface'])
        self.assertEqual(legacy['skills'], './skills/')
        self.assertEqual(legacy['mcpServers'], './.mcp.json')
        for filename, transport in [('mcp.json', 'streamable-http'), ('.mcp.json', 'http')]:
            server = json.loads(self.files[filename])['mcpServers']['forgegui']
            self.assertEqual(set(server), {'type', 'url'})
            self.assertEqual(server['type'], transport)
        for path in self.files:
            self.assertFalse(set(Path(path).parts) & {'hooks', '__pycache__', '.claude-plugin', '.env'})
        for filename in ('plugin.json', '.codex-plugin/plugin.json', 'mcp.json', '.mcp.json'):
            for forbidden in (b'userConfig', b'headers', b'${', b'"apps"', b'"hooks"'):
                self.assertNotIn(forbidden, self.files[filename])

    def test_portable_official_schemas(self):
        for kind in ('plugin', 'mcp'):
            schema = json.loads((ROOT / f'tests/schemas/openai-{kind}.schema.json').read_text())
            Draft202012Validator.check_schema(schema)
            validator = Draft202012Validator(schema)
            document = json.loads(self.files[f'{kind}.json'])
            validator.validate(document)
            document['unexpected'] = True
            self.assertTrue(list(validator.iter_errors(document)))

    def test_inventory_rejects_forbidden_and_missing_sources(self):
        inventory_path = ROOT / 'release/openai/sources.json'
        original = Path.read_text
        for entry in ('../escape.md', 'hooks/Stop.sh', '.env', '__pycache__/cache.py', 'missing.md'):
            def read(path, *args, **kwargs):
                if path == inventory_path:
                    return json.dumps(['SKILL.md', entry])
                return original(path, *args, **kwargs)
            with self.subTest(entry=entry), patch.object(Path, 'read_text', read):
                with self.assertRaises((ValueError, OSError)):
                    package.expected_files()

    def test_runtime_boundaries_and_safety_are_in_skill(self):
        skill = self.files[f'skills/{package.NAME}/SKILL.md'].decode()
        for required in ('Remote-only ChatGPT or Codex', 'Studio-capable Codex',
                         'Do not apply the mandatory Studio preflight', 'numeric ceiling',
                         'outcome_unknown', 'request_id', 'tenant', 'pinned',
                         'downloadable artifact', 'Never claim Studio edits', 'There is no Stop hook',
                         'OAuth readiness', 'Legacy publication is replay-only'):
            self.assertIn(required, skill)


if __name__ == '__main__':
    unittest.main()
