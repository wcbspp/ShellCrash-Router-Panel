import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BootWatchdogTests(unittest.TestCase):
 def run_case(self,started,manual=False,pending=False,disabled=False,deferred=False):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);ram=d/'ram';ram.mkdir();admin=d/'admin';admin.mkdir();c=d/'persist';(c/'starts').mkdir(parents=True);bin=d/'bin';bin.mkdir()
   (bin/'pidof').write_text('#!/bin/sh\nexit 1\n');(bin/'pidof').chmod(0o755)
   for name in ['panel_boot.sh','incident_record.sh']:
    p=c/'starts'/name;p.write_text('#!/bin/sh\necho called >> "'+str(d/'called')+'"\n');p.chmod(0o755)
   (d/'uptime').write_text('600.00 200.00\n')
   if started:(ram/'crash_start_time').write_text('1')
   if manual:(ram/'manual-stop').touch()
   if pending:(ram/'boot-pending').touch()
   if disabled:(c/'.dis_startup').touch()
   if deferred:(admin/'boot-retry-due').write_text('999999999')
   script=(ROOT/'payload/starts/start_legacy_wd.sh').read_text().replace('/tmp/ShellCrash',str(ram)).replace('/tmp/sc-admin',str(admin)).replace('/proc/uptime',str(d/'uptime'))
   p=d/'watchdog.sh';p.write_text(script)
   result=subprocess.run(['sh',str(p),'shellcrash'],env=dict(os.environ,CRASHDIR=str(c),PATH=str(bin)+':'+os.environ['PATH']),capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr)
   return (d/'called').exists(),(admin/'recoveries').read_text().strip() if (admin/'recoveries').exists() else None
 def test_first_boot_missing_core_is_not_a_crash(self):self.assertEqual(self.run_case(False),(False,None))
 def test_missing_core_after_start_still_recovers(self):self.assertEqual(self.run_case(True),(True,'1'))
 def test_manual_stop_never_recovers(self):self.assertEqual(self.run_case(True,True),(False,None))

 def test_pending_first_boot_retries_without_crash_count(self):self.assertEqual(self.run_case(False,pending=True),(True,None))
 def test_manual_stop_cancels_pending_boot_retry(self):self.assertEqual(self.run_case(False,manual=True,pending=True),(False,None))
 def test_disabled_autostart_cancels_pending_boot_retry(self):self.assertEqual(self.run_case(False,pending=True,disabled=True),(False,None))
 def test_pending_boot_retry_respects_backoff(self):self.assertEqual(self.run_case(False,pending=True,deferred=True),(False,None))

 def test_startup_firewall_cleanup_is_not_a_manual_stop(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);ram=d/'ram';source=(ROOT/'payload/starts/fw_stop.sh').read_text().split('. "$CRASHDIR"/libs/get_config.sh',1)[0].replace('/tmp/ShellCrash',str(ram))
   p=d/'cleanup.sh';p.write_text(source)
   result=subprocess.run(['sh',str(p)],env=dict(os.environ,CRASHDIR=str(d),SC_PANEL_STARTING='1'),capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertFalse((ram/'manual-stop').exists())
   env=dict(os.environ,CRASHDIR=str(d));env.pop('SC_PANEL_STARTING',None)
   result=subprocess.run(['sh',str(p)],env=env,capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertTrue((ram/'manual-stop').exists())
