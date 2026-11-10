import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'shared/lib/oom-remote.sh'


class OomRemote(unittest.TestCase):
 def setUp(self):
  self.tmp = tempfile.TemporaryDirectory()
  self.addCleanup(self.tmp.cleanup)
  root = Path(self.tmp.name)
  self.config = root / 'configs'
  self.config.mkdir()
  (root / 'starts').mkdir()
  (root / 'starts/resource_health.sh').write_text('resource_limits(){ rh_protect_mb=${TEST_PROTECT:-12}; }\n')
  (root / 'starts/remote.sh').write_text('''
remote_transport(){ echo webdav; }
remote_ready(){ return 0; }
remote_hash(){ sha256sum | cut -d " " -f1; }
dav_base(){ echo https://example.invalid/shellcrash-panel/K2P; }
dav_mkdir(){ return 0; }
dav_store_file(){ [ "${TEST_FAIL:-0}" = 0 ]; }
''')
  self.record = root / 'record'
  self.record.write_text('oom evidence')
  bindir = root / 'bin'
  bindir.mkdir()
  awk = bindir / 'awk'
  awk.write_text('#!/bin/sh\necho "${TEST_AVAILABLE:-20000}"\n')
  awk.chmod(0o755)
  self.env = dict(os.environ, CRASHDIR=str(root), SC_OOM_RUNTIME=str(root), PATH=str(bindir) + ':' + os.environ['PATH'])

 def run_upload(self):
  return subprocess.run(['sh', str(SCRIPT), str(self.record)], env=self.env, capture_output=True, text=True)

 def test_disabled_and_success(self):
  self.assertEqual(self.run_upload().stdout, '')
  (self.config / 'oom-remote-enabled').touch()
  result = self.run_upload()
  self.assertEqual(result.returncode, 0)
  self.assertEqual(len(result.stdout.strip()), 64)

 def test_failure_and_size_limit(self):
  (self.config / 'oom-remote-enabled').touch()
  self.env['TEST_FAIL'] = '1'
  self.assertNotEqual(self.run_upload().returncode, 0)
  self.env['TEST_FAIL'] = '0'
  self.record.write_bytes(b'x' * 65537)
  self.assertNotEqual(self.run_upload().returncode, 0)

 def test_respects_configured_memory_limit(self):
  (self.config / 'oom-remote-enabled').touch()
  self.env['TEST_AVAILABLE'] = '12287'
  self.assertNotEqual(self.run_upload().returncode, 0)
  self.env['TEST_AVAILABLE'] = '12288'
  self.assertEqual(self.run_upload().returncode, 0)
  self.env['TEST_PROTECT'] = '14'
  self.assertNotEqual(self.run_upload().returncode, 0)


if __name__ == '__main__':
 unittest.main()
