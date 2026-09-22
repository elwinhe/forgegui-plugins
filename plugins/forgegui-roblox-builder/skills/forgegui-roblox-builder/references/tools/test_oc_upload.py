"""No-network publisher regression tests; all API access is mocked."""
import contextlib
from email import policy
from email.parser import BytesParser
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import oc_upload as u


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.file = self.root / 'one.png'
        self.file.write_bytes(b'image')
        self.receipt = self.root / 'receipt.json'
        self.argv = [str(self.file), '--user-id', '123', '--receipt', str(self.receipt)]
        self.env = patch.dict(os.environ, {'ROBLOX_API_KEY': 'secret-test-key'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.calls = []
        self.auth = {'enabled': True, 'expired': False, 'authorizedUserId': 123,
                     'scopes': [{'name': 'asset', 'operations': ['read', 'write'],
                                 'userIds': ['*'], 'groupIds': ['456']}]}
        self.api = patch.object(u, 'call', side_effect=self.fake)
        self.api.start()
        self.addCleanup(self.api.stop)

    def saved(self):
        return json.loads(self.receipt.read_text())

    def fake(self, url, key, data=None, content_type=None, **kwargs):
        self.calls.append(url)
        if url == u.INTROSPECT:
            self.assertEqual(json.loads(data), {'apiKey': 'secret-test-key'})
            return self.auth
        entries = self.saved()['entries']
        if url.endswith('/assets'):
            self.assertTrue(any(e['state'] == 'submitting' for e in entries))
            return {'path': 'operations/op-1'}
        self.assertTrue(any(e.get('operation') == 'op-1' and e['state'] == 'polling' for e in entries))
        return {'done': True, 'response': {'assetId': '999'}}

    def run_cli(self, args=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            result = u.main(self.argv if args is None else args)
        self.assertNotIn('secret-test-key', out.getvalue())
        if self.receipt.exists():
            self.assertNotIn('secret-test-key', self.receipt.read_text())
        return result

    def test_success_ordering_and_replay(self):
        self.assertEqual(self.run_cli(), 0)
        self.assertEqual(self.saved()['entries'][0]['state'], 'succeeded')
        self.calls.clear()
        self.assertEqual(self.run_cli(self.argv + ['--resume']), 0)
        self.assertEqual(self.calls, [u.INTROSPECT])
        self.assertEqual(self.run_cli(), 1)

    def test_partial_batch_failure_retains_first(self):
        second = self.root / 'two.png'
        second.write_bytes(b'second')
        base = self.fake
        def fail_second(url, *args, **kwargs):
            if url.endswith('/assets') and self.saved()['entries'][1]['state'] == 'submitting':
                self.assertEqual(self.saved()['entries'][0]['assetId'], '999')
                raise u.UploadError('API request failed.')
            return base(url, *args, **kwargs)
        with patch.object(u, 'call', side_effect=fail_second):
            self.assertEqual(self.run_cli([str(second)] + self.argv), 1)
        self.assertEqual(self.saved()['entries'][0]['assetId'], '999')
        self.calls.clear()
        self.assertEqual(self.run_cli([str(second)] + self.argv + ['--resume']), 1)
        self.assertEqual(self.calls, [])

    def test_lost_or_malformed_submission_never_reposts(self):
        for reply in [None, {}, {'path': 'https://evil.test/op'}, {'operationId': '../x'},
                      {'operationId': 'one', 'path': 'operations/two'}]:
            with self.subTest(reply=reply):
                if self.receipt.exists():
                    self.receipt.unlink()
                def broken(url, *args, **kwargs):
                    if url == u.INTROSPECT:
                        return self.auth
                    if reply is None:
                        raise u.UploadError('Transport failure.')
                    return reply
                with patch.object(u, 'call', side_effect=broken):
                    self.assertEqual(self.run_cli(), 1)
                self.assertEqual(self.saved()['entries'][0]['state'], 'submitting')
                self.calls.clear()
                self.assertEqual(self.run_cli(self.argv + ['--resume']), 1)
                self.assertEqual(self.calls, [])

    def test_poll_error_and_resume_only_polling(self):
        base = self.fake
        def fail_poll(url, *args, **kwargs):
            if '/operations/' in url:
                raise u.UploadError('Poll failed.')
            return base(url, *args, **kwargs)
        with patch.object(u, 'call', side_effect=fail_poll):
            self.assertEqual(self.run_cli(), 1)
        self.assertEqual(self.saved()['entries'][0]['state'], 'polling')
        self.calls.clear()
        self.assertEqual(self.run_cli(self.argv + ['--resume']), 0)
        self.assertEqual(self.calls, [u.INTROSPECT, u.API + '/operations/op-1'])

    def test_timeout_retains_operation(self):
        with patch.object(u.time, 'monotonic', side_effect=[0, 2]):
            self.assertEqual(self.run_cli(self.argv + ['--timeout', '1']), 1)
        self.assertEqual(self.saved()['entries'][0]['operation'], 'op-1')

    def test_drift_and_malformed_receipts(self):
        self.assertEqual(self.run_cli(), 0)
        original = self.receipt.read_text()
        for change in ['owner', 'name', 'bytes', 'invalid', 'missing', 'operation']:
            with self.subTest(change=change):
                self.receipt.write_text(original)
                self.file.write_bytes(b'image')
                args = self.argv + ['--resume']
                if change == 'owner':
                    args = [a if a != '123' else '124' for a in args]
                elif change == 'name':
                    args += ['--name', 'different']
                elif change == 'bytes':
                    self.file.write_bytes(b'changed')
                elif change == 'invalid':
                    self.receipt.write_text('{')
                elif change == 'missing':
                    self.receipt.write_text('{}')
                else:
                    data = self.saved()
                    data['entries'][0]['operation'] = 'https://evil.test'
                    self.receipt.write_text(json.dumps(data))
                self.calls.clear()
                self.assertEqual(self.run_cli(args), 1)
                self.assertEqual(self.calls, [])

    def test_authority_fail_closed(self):
        original = json.loads(json.dumps(self.auth))
        for change in ['disabled', 'expired', 'owner', 'scope', 'read', 'groups_wildcard', 'groups_missing']:
            with self.subTest(change=change):
                self.auth = json.loads(json.dumps(original))
                args = self.argv
                if change == 'disabled': self.auth['enabled'] = False
                if change == 'expired': self.auth['expired'] = True
                if change == 'owner': self.auth['authorizedUserId'] = 999
                if change == 'scope': self.auth['scopes'] = []
                if change == 'read': self.auth['scopes'][0]['operations'] = ['write']
                if change.startswith('groups'):
                    args = [str(self.file), '--group-id', '456', '--receipt', str(self.receipt)]
                    self.auth['scopes'][0]['groupIds'] = ['*'] if change.endswith('wildcard') else []
                self.calls.clear()
                self.assertEqual(self.run_cli(args), 1)
                self.assertEqual(self.calls, [u.INTROSPECT])
                self.assertFalse(self.receipt.exists())
        self.auth = original
        args = [str(self.file), '--group-id', '456', '--receipt', str(self.receipt)]
        self.assertEqual(self.run_cli(args), 0)

    def test_concurrent_writer(self):
        with u.locked(self.receipt):
            self.assertEqual(self.run_cli(), 1)
        self.assertEqual(self.calls, [])

    def test_failed_intent_persistence_prevents_post(self):
        real = u.atomic_write
        def fail_intent(path, value):
            if value['entries'][0]['state'] == 'submitting':
                raise OSError('secret-test-key')
            real(path, value)
        with patch.object(u, 'atomic_write', side_effect=fail_intent):
            self.assertEqual(self.run_cli(), 1)
        self.assertEqual(self.calls, [u.INTROSPECT])

    def test_failed_operation_persistence_prevents_poll(self):
        real = u.atomic_write
        def fail_operation(path, value):
            if value['entries'][0]['state'] == 'polling':
                raise OSError('failure')
            real(path, value)
        with patch.object(u, 'atomic_write', side_effect=fail_operation):
            self.assertEqual(self.run_cli(), 1)
        self.assertEqual(self.calls, [u.INTROSPECT, u.API + '/assets'])
        self.assertEqual(self.saved()['entries'][0]['state'], 'submitting')
        self.calls.clear()
        self.assertEqual(self.run_cli(self.argv + ['--resume']), 1)
        self.assertEqual(self.calls, [])

    def test_required_destination_and_receipt(self):
        invalid = [
            [str(self.file), '--receipt', str(self.receipt)],
            [str(self.file), '--user-id', '123'],
        ]
        for flag in ['--user-id', '--group-id']:
            for owner in ['', '0', '-1', 'abc', '1.5']:
                invalid.append([str(self.file), flag, owner, '--receipt', str(self.receipt)])
        for args in invalid:
            with self.subTest(args=args):
                try:
                    self.assertNotEqual(self.run_cli(args), 0)
                except SystemExit as error:
                    self.assertEqual(error.code, 2)
                self.assertEqual(self.calls, [])
                self.assertFalse(self.receipt.exists())

    def test_supported_multipart_mappings(self):
        mappings = [('.png', 'Image', 'image/png'),
                    ('.mp3', 'Audio', 'audio/mpeg'),
                    ('.glb', 'Model', 'model/gltf-binary'),
                    ('.rbxm', 'Animation', 'model/x-rbxm'),
                    ('.rbxm', 'Model', 'model/x-rbxm')]
        self.assertEqual(set(u.FORMATS), {item[0] for item in mappings})
        for suffix, kind, mime in mappings:
            for flag, creator in [('--user-id', {'userId': '123'}),
                                  ('--group-id', {'groupId': '456'})]:
                with self.subTest(suffix=suffix, kind=kind, creator=creator):
                    if self.receipt.exists():
                        self.receipt.unlink()
                    # Uppercase extension and unsafe basename must not reach MIME headers.
                    source = self.root / ('unsafe"\r\nname' + suffix.upper())
                    payload = b'\x00binary\xff\r\nasset bytes'
                    source.write_bytes(payload)
                    bodies = []
                    base = self.fake
                    def inspect(url, key, data=None, content_type=None, **kwargs):
                        if url.endswith('/assets'):
                            message = BytesParser(policy=policy.default).parsebytes(
                                ('Content-Type: ' + content_type + '\r\nMIME-Version: 1.0\r\n\r\n').encode() + data)
                            parts = list(message.iter_parts())
                            self.assertEqual(len(parts), 2)
                            metadata = json.loads(parts[0].get_payload(decode=True))
                            self.assertEqual(metadata['assetType'], kind)
                            self.assertEqual(metadata['displayName'], 'Test asset')
                            self.assertEqual(metadata['creationContext']['creator'], creator)
                            self.assertEqual(parts[1].get_filename(), 'asset' + suffix)
                            self.assertEqual(parts[1].get_content_type(), mime)
                            self.assertEqual(parts[1].get_payload(decode=True), payload)
                            bodies.append(data)
                        return base(url, key, data, content_type, **kwargs)
                    with patch.object(u, 'call', side_effect=inspect):
                        args = [str(source), '--type', kind, '--name', 'Test asset', flag,
                                next(iter(creator.values())), '--receipt', str(self.receipt)]
                        self.assertEqual(self.run_cli(args), 0)
                    self.assertEqual(len(bodies), 1)

    def test_unexercised_formats_refused_by_both_entry_points(self):
        wrapper = pathlib.Path(u.__file__).resolve().parents[2] / 'scripts/open_cloud_upload.sh'
        for suffix, kind in [('.jpg', 'Image'), ('.jpeg', 'Image'),
                             ('.fbx', 'Model'), ('.ogg', 'Audio')]:
            with self.subTest(suffix=suffix):
                source = self.root / ('asset' + suffix)
                source.write_bytes(b'asset')
                self.assertEqual(self.run_cli([str(source), '--type', kind, '--user-id', '123',
                                              '--receipt', str(self.receipt)]), 1)
                result = subprocess.run(
                    ['bash', str(wrapper), '--dry-run', str(source), kind, 'Test asset',
                     '--user-id', '123', '--receipt', str(self.receipt)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertIn('Unsupported file format/type combination.', result.stderr)
                self.assertEqual(self.calls, [])
                self.assertFalse(self.receipt.exists())

    def test_preflight(self):
        for extra in [['--group-id', '456'], ['--type', 'Audio'], ['--timeout', 'nan']]:
            with self.subTest(extra=extra):
                try:
                    self.assertNotEqual(self.run_cli(self.argv + extra), 0)
                except SystemExit as e:
                    self.assertEqual(e.code, 2)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.run_cli(self.argv + ['--dry-run']), 0)
        self.assertFalse(self.receipt.exists())
        with patch.dict(os.environ, {}, clear=True):
            (self.root / '.env').write_text('ROBLOX_API_KEY=secret-test-key')
            self.assertEqual(self.run_cli(), 1)

    def test_wrapper_real_dry_run_and_delegation(self):
        wrapper = pathlib.Path(u.__file__).resolve().parents[2] / 'scripts/open_cloud_upload.sh'
        result = subprocess.run(['bash', str(wrapper), '--dry-run', str(self.file), 'Image', 'test',
                                 '--user-id', '123', '--receipt', str(self.receipt)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Dry run', result.stdout)
        # A fake interpreter records arguments; wrapper has no API path of its own.
        fake = self.root / 'python3'
        fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        fake.chmod(0o700)
        for flags in [[], ['--dry-run']]:
            for extra in [[], ['--group-id', '456', '--receipt', 'receipt with spaces.json', '--resume']]:
                with self.subTest(flags=flags, extra=extra):
                    result = subprocess.run(
                        ['bash', str(wrapper), *flags, 'asset with spaces.png', 'Image',
                         'name with spaces', *extra],
                        env={**os.environ, 'PATH': str(self.root) + ':' + os.environ['PATH']},
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = result.stdout.splitlines()
                    self.assertEqual(pathlib.Path(args[0]).resolve(), pathlib.Path(u.__file__).resolve())
                    self.assertEqual(args[1:], flags + ['--type', 'Image', '--name',
                                     'name with spaces', *extra, '--', 'asset with spaces.png'])


class TransportTests(unittest.TestCase):
    def test_raw_error_not_exposed_and_no_retry(self):
        with patch.object(u.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = RuntimeError('SECRET raw body')
            with self.assertRaises(u.UploadError) as error:
                u.call(u.API + '/assets', 'SECRET', b'data')
            self.assertNotIn('SECRET', str(error.exception))
            self.assertEqual(factory.return_value.open.call_count, 1)

    def test_arbitrary_url_and_redirect_refused(self):
        with self.assertRaises(u.UploadError):
            u.call('https://evil.test', 'SECRET')
        with self.assertRaises(u.UploadError):
            u.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://evil.test')


if __name__ == '__main__':
    unittest.main()
