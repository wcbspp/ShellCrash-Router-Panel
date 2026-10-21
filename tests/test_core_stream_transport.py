"""Routing/authentication contracts; these fixtures are not device validation."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'profiles/k2p/payload/starts/core_release.sh'


class StreamTransport(unittest.TestCase):
    def exercise(self, cached_blob='a'*40, upload=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            c, d, commands = root/'c', root/'runtime', root/'bin'
            for p in (c/'starts', c/'configs', d/'core-check', commands):
                p.mkdir(parents=True, exist_ok=True)
            (c/'starts/panel_env.sh').write_text(f'C={c}\nD={d}\n')
            (root/'meminfo').write_text('MemAvailable: 1000000 kB\n')
            source = root/'core_release.sh'
            source.write_text(SOURCE.read_text().replace('/proc/meminfo', str(root/'meminfo')))
            (root/'cached').write_text('version=1.12.13\narch=mipsle-softfloat\nvariant=singbox\n'
                'archive_size=1000000\ngit_blob='+cached_blob+'\nsha256='+'b'*64+
                '\nurl=http://untrusted.invalid/do-not-follow\n')
            upload_action = "sha256sum \"$2\" | awk '{print $1}'" if upload else 'return 1'
            (c/'starts/mirror_lib.sh').write_text(f'''
remote_transport(){{ echo webdav; }}
remote_ready(){{ return 0; }}
remote_manifest(){{ cat '{root}/cached'; }}
dav_object(){{ printf 'http://configured.invalid/objects/core-%s.tar.gz\n' "$2"; }}
mirror_core_url(){{ return 1; }}
remote_put(){{ {upload_action}; }}
''')
            (commands/'stat').write_text('#!/usr/bin/env python3\nimport os,sys\nprint(os.stat(sys.argv[-1]).st_size)\n')
            (commands/'sha256sum').write_text('#!/usr/bin/env python3\nimport hashlib,pathlib,sys\nprint(hashlib.sha256(pathlib.Path(sys.argv[-1]).read_bytes()).hexdigest()+"  "+sys.argv[-1])\n')
            (commands/'lua').write_text(r'''#!/usr/bin/env python3
import json,os,pathlib,sys
with open(os.environ['CORE_CALL_LOG'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\n')
assert not pathlib.Path(os.environ['CORE_SEED_PATH']).exists(), 'compressed copy retained during extraction'
pathlib.Path(sys.argv[7]).write_text('sha256='+'c'*64+'\nbinary_size=1000000\n')
''')
            for p in commands.iterdir():
                p.chmod(0o755)
            candidate = d/'candidate.info'
            candidate.write_text('version=1.13.14\narch=mipsle-softfloat\nvariant=singbox\n'
                'archive_size=1000000\ngit_blob='+'a'*40+'\nurl=https://source.invalid/pinned.tar.gz\n')
            script = f'''
export CRASHDIR='{c}'
. '{source}'
core_cacerts(){{ printf cert > "$D/core-check/ca.pem"; }}
release_download(){{ printf verified-source-body > "$2"; }}
release_stream_core '{candidate}' '{d}/binary' '{d}/receipt'
'''
            env = dict(os.environ, PATH=str(commands)+':'+os.environ['PATH'],
                       CORE_CALL_LOG=str(root/'calls'),
                       CORE_SEED_PATH=str(d/'core-check/stream-preseed.tgz'))
            result = subprocess.run(['sh'], input=script, text=True, env=env,
                                    capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            return [json.loads(x) for x in (root/'calls').read_text().splitlines()], (d/'receipt').read_text()

    def test_matching_pinned_cache_uses_configured_host_and_auth(self):
        calls, receipt = self.exercise()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], 'http://configured.invalid/objects/core-'+'b'*64+'.tar.gz')
        self.assertEqual(calls[0][3:5], ['a'*40, 'b'*64])
        self.assertTrue(calls[0][-1].endswith('/configs/webdav.auth'))
        self.assertIn('stream_transport=webdav-cache', receipt)

    def test_other_blob_cannot_select_cache_or_metadata_url(self):
        calls, receipt = self.exercise(cached_blob='d'*40)
        digest = hashlib.sha256(b'verified-source-body').hexdigest()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], 'http://configured.invalid/objects/core-'+digest+'.tar.gz')
        self.assertEqual(calls[0][3:5], ['a'*40, digest])
        self.assertIn('stream_transport=webdav-preseed', receipt)

    def test_failed_upload_falls_back_without_repository_credentials(self):
        calls, receipt = self.exercise(cached_blob='d'*40, upload=False)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], 'https://source.invalid/pinned.tar.gz')
        self.assertEqual(len(calls[0]), 9)  # helper script plus its eight arguments
        self.assertNotIn('webdav.auth', ' '.join(calls[0]))
        self.assertNotIn('stream_transport=webdav', receipt)


if __name__ == '__main__':
    unittest.main()
