import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class ConfigurationCoreTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.p=Path(self.temp.name)
  for name in ['configs','starts','ram','proc/37','bin']:(self.p/name).mkdir(parents=True)
  self.helper=self.p/'helper.sh';self.helper.write_text((ROOT/'payload/starts/config_core.sh').read_text().replace('/tmp/ShellCrash',str(self.p/'ram')))
  (self.p/'configs/core-installed.info').write_text('version=1.12.13\n')
  (self.p/'starts/core_release.sh').write_text('release_get(){ echo 9025081; }\n')
  f=self.p/'starts/download_core.sh';f.write_text('#!/bin/sh\ntouch "'+str(self.p/'downloaded')+'"\nexit 1\n');f.chmod(0o700)
  pid=self.p/'bin/pidof';pid.write_text('#!/bin/sh\necho 37\n');pid.chmod(0o700)
 def run_shell(self,body,available=19588):
  script='C="$1";D="$1";SC_PROC_ROOT="$1/proc"; . "$1/helper.sh"; fail(){ echo "$1"; };event(){ :; };resource_read(){ rh_available='+str(available)+';rh_protect_mb=12; };'+body
  return subprocess.run(['sh','-c',script,'test',str(self.p)],env=dict(os.environ,PATH=str(self.p/'bin')+':'+os.environ['PATH']),capture_output=True,text=True)
 def executable(self,version='1.12.13'):
  exe=self.p/'proc/37/exe';exe.write_text('#!/bin/sh\necho "sing-box version '+version+'"\n');exe.chmod(0o700);return exe
 def test_running_binary_at_19mb_does_not_stage_archive_and_fd_survives_unlink(self):
  exe=self.executable();r=self.run_shell('configuration_core_prepare || exit 1; rm "$SC_PROC_ROOT/37/exe"; cat <&3; configuration_core_release')
  self.assertEqual(r.returncode,0,r.stderr);self.assertIn('sing-box version 1.12.13',r.stdout);self.assertFalse((self.p/'downloaded').exists())
 def test_missing_runtime_at_19mb_has_distinct_preparation_error_and_does_not_download(self):
  r=self.run_shell('configuration_core_prepare');self.assertNotEqual(r.returncode,0);self.assertIn('core_staging_memory_insufficient',r.stdout);self.assertFalse((self.p/'downloaded').exists())
 def test_version_mismatch_never_stops_or_downloads(self):
  self.executable('1.12.14');r=self.run_shell('configuration_core_prepare');self.assertNotEqual(r.returncode,0);self.assertIn('core_runtime_mismatch',r.stdout);self.assertFalse((self.p/'downloaded').exists())
 def test_missing_runtime_with_room_attempts_download_and_reports_failure(self):
  r=self.run_shell('configuration_core_prepare',40960);self.assertNotEqual(r.returncode,0);self.assertIn('core_download_failed',r.stdout);self.assertTrue((self.p/'downloaded').exists())
if __name__=='__main__':unittest.main()
