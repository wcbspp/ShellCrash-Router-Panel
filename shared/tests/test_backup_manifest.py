import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'ax5' if (ROOT/'ax5').is_dir() else ROOT/'payload/starts'


class BackupManifest(unittest.TestCase):
    def record(self):
        return {'format': 2, 'scope': 'full-application', 'model': 'K2P', 'core_kind': 'singbox',
                'core_version': '1.12.13', 'core_sha256': 'b'*64,
                'label': '当前可用版本', 'files': [
                    {'name': name, 'path': name, 'size': 123, 'sha256': digest*64}
                    for name, digest in [('application.tar.gz', 'a'), ('core.tar.gz', 'b'), ('runtime-assets.tar.gz', 'c')]]}

    def parse(self, data, model='K2P'):
        if not isinstance(data, str): data=json.dumps(data, ensure_ascii=False, indent=2)
        return subprocess.run(['awk', '-v', 'expected_model='+model, '-f', str(SOURCE/'backup-manifest.awk')],
                              input=data, text=True, capture_output=True, timeout=4, env={**os.environ, 'LC_ALL':'C'})

    def test_pretty_and_compact_complete_manifests_only_emit_safe_records(self):
        for compact in [False, True]:
            data=self.record()
            result=self.parse(json.dumps(data, ensure_ascii=False, separators=(',', ':')) if compact else data)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(result.stdout.splitlines()), 6)
            self.assertNotIn('label', result.stdout)

    def test_missing_wrong_model_duplicate_and_partial_records_rejected(self):
        for mode in ['wrong_model', 'missing', 'duplicate', 'meta', 'mismatch_hash', 'oversize', 'unknown']:
            with self.subTest(mode=mode):
                data=self.record()
                if mode=='wrong_model': data['model']='AX5'
                if mode=='missing': data['files'].pop()
                if mode=='duplicate': data['files'].append(data['files'][0])
                if mode=='meta': data['core_kind']='meta'
                if mode=='mismatch_hash': data['core_sha256']='a'*64
                if mode=='oversize': data['files'][0]['size']=4000001
                if mode=='unknown': data['files'][0]['name']='firmware.bin'
                result=self.parse(data);self.assertNotEqual(result.returncode, 0);self.assertEqual(result.stdout, '')

    def test_traversal_shell_strings_external_urls_and_escaped_fields_rejected(self):
        for path in ['../outside', '/etc/passwd', 'objects/../../secret', 'https://server/core.tar.gz',
                     'objects//file', '$(touch pwned)', '`touch pwned`', 'file\nname', 'objects\\file', 'objects/./file']:
            data=self.record(); data['files'][0]['path']=path
            result=self.parse(data);self.assertNotEqual(result.returncode, 0);self.assertEqual(result.stdout, '')
        raw=json.dumps(self.record()).replace('"format": 2', '"format": 1, "format": 2')
        self.assertNotEqual(self.parse(raw).returncode, 0)

    def test_trailing_data_depth_and_size_are_bounded(self):
        for data in [json.dumps(self.record())+'{}', '['*30+']'*30, ' '*16385,
                     '{"files/0/name":"core.tar.gz"}', '{"format":02}', '{"format":2,}']:
            result=self.parse(data);self.assertNotEqual(result.returncode, 0);self.assertEqual(result.stdout, '')


if __name__ == '__main__': unittest.main()
