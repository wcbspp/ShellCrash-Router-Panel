import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'profiles/k2p/payload/starts/save_storage.sh').read_text()
class StorageReadback(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.p=Path(self.tmp.name)
  for n in ('storage','bin','hashes'):(self.p/n).mkdir()
  (self.p/'storage/config').write_text('safe configuration data\n'*10)
  (self.p/'mtd').write_text('mtd6: 00080000 00010000 "Storage"\n')
  self.flash=self.p/'flash';self.calls=self.p/'calls';self.script=self.p/'save.sh'
  source=SOURCE.replace('/tmp/shellcrash-storage-save.lock',str(self.p/'lock')).replace('/tmp/shellcrash-storage-save.tar.bz2',str(self.p/'archive')).replace('/tmp/hashes',str(self.p/'hashes')).replace('cd /etc/storage','cd '+str(self.p/'storage')).replace('/proc/mtd',str(self.p/'mtd')).replace('"/dev/mtd$index"','"$TEST_FLASH"')
  self.script.write_text(source)
  shim=self.p/'bin/mtd_write';shim.write_text('#!/bin/sh\necho write >> "$TEST_CALLS"\ncp "$2" "$TEST_FLASH"\n[ "${TEST_CORRUPT:-0}" = 0 ] || printf broken > "$TEST_FLASH"\n');shim.chmod(0o755)
  stat=self.p/'bin/stat';stat.write_text('#!/bin/sh\npython3 -c \"import os,sys;print(os.stat(sys.argv[1]).st_size)\" \"$3\"\n');stat.chmod(0o755)
  self.env=dict(os.environ,PATH=str(self.p/'bin')+':'+os.environ['PATH'],TEST_FLASH=str(self.flash),TEST_CALLS=str(self.calls),SC_STORAGE_VERIFY='1',SC_STORAGE_MAX_BYTES='499712')
 def run_save(self,**kw):return subprocess.run(['sh',str(self.script)],env=dict(self.env,**kw),capture_output=True,text=True)
 def test_verify_and_stale_cache(self):
  self.assertEqual(self.run_save().returncode,0)
  self.flash.write_text('stale disk image')
  self.assertEqual(self.run_save().returncode,0)
  self.assertEqual(len(self.calls.read_text().splitlines()),2)
 def test_mismatch_and_overlimit_are_failure(self):
  self.assertNotEqual(self.run_save(TEST_CORRUPT='1').returncode,0)
  self.calls.unlink()
  self.assertNotEqual(self.run_save(SC_STORAGE_MAX_BYTES='16').returncode,0)
  self.assertFalse(self.calls.exists())

 def test_standard_save_does_not_require_oom_readback(self):
  result=self.run_save(SC_STORAGE_VERIFY='0')
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
