import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import glb_quality as quality


def modified_cube(change):
    original = quality._cube_glb()
    length = struct.unpack_from('<I', original, 12)[0]
    document = json.loads(original[20:20 + length])
    change(document)
    encoded = json.dumps(document).encode()
    encoded += b' ' * (-len(encoded) % 4)
    body = struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + original[20 + length:]
    return struct.pack('<III', 0x46546C67, 2, 12 + len(body)) + body


class ReaderTests(unittest.TestCase):
    def test_unsupported_geometry_is_explicit(self):
        changes = [
            lambda g: g['meshes'][0]['primitives'][0].update(mode=1),
            lambda g: g['accessors'][0].update(sparse={'count': 1}),
            lambda g: g.update(extensionsUsed=['KHR_draco_mesh_compression']),
            lambda g: g['bufferViews'][0].update(extensions={'EXT_meshopt_compression': {}}),
            lambda g: g['buffers'][0].update(uri='external.bin'),
            lambda g: g['accessors'][0].update(componentType=5123),
        ]
        for change in changes:
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'Unsupported geometry'):
                quality._report_bytes(modified_cube(change))

    def test_partial_triangles_are_not_silently_truncated(self):
        with self.assertRaisesRegex(ValueError, 'Invalid triangle geometry'):
            quality._report_bytes(modified_cube(lambda g: g['accessors'][1].update(count=35)))

    def test_material_primitives_are_not_joined(self):
        def split(g):
            g['accessors'][1]['count'] = 18
            g['accessors'].append(dict(g['accessors'][1], byteOffset=36))
            g['meshes'][0]['primitives'].append({'attributes': {'POSITION': 0}, 'indices': 2})
        rows = quality._report_bytes(modified_cube(split))
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(row['boundary_edges'] > 0 for row in rows))

    def test_cli_failure_keeps_processing(self):
        with tempfile.TemporaryDirectory() as directory:
            valid = Path(directory) / 'valid.glb'
            invalid = Path(directory) / 'invalid.glb'
            valid.write_bytes(quality._cube_glb())
            invalid.write_bytes(b'invalid')
            for extra in ([], ['--md']):
                result = subprocess.run([sys.executable, quality.__file__, *extra, str(invalid), str(valid)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('ERROR', result.stdout)
                self.assertIn('cube[0]', result.stdout)
            result = subprocess.run([sys.executable, quality.__file__, str(valid)], capture_output=True)
            self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
