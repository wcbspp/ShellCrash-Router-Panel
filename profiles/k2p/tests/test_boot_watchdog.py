import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BootWatchdogTests(unittest.TestCase):
 def run_case(self,started,manual=False):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);ram=d/'ram';ram.mkdir();admin=d/'admin';c=d/'persist';(c/'starts').mkdir(parents=True);bin=d/'bin';bin.mkdir()
   (bin/'pidof').write_text('#!/bin/sh\nexit 1\n');(bin/'pidof').chmod(0o755)
   for name in ['panel_boot.sh','incident_record.sh']:
    p=c/'starts'/name;p.write_text('#!/bin/sh\necho called >> "'+str(d/'called')+'"\n');p.chmod(0o755)
   if started:(ram/'crash_start_time').write_text('1')
   if manual:(ram/'manual-stop').touch()
   script=(ROOT/'payload/starts/start_legacy_wd.sh').read_text().replace('/tmp/ShellCrash',str(ram)).replace('/tmp/sc-admin',str(admin))
   p=d/'watchdog.sh';p.write_text(script)
   result=subprocess.run(['sh',str(p),'shellcrash'],env=dict(os.environ,CRASHDIR=str(c),PATH=str(bin)+':'+os.environ['PATH']),capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr)
   return (d/'called').exists(),(admin/'recoveries').read_text().strip() if (admin/'recoveries').exists() else None
 def test_first_boot_missing_core_is_not_a_crash(self):self.assertEqual(self.run_case(False),(False,None))
 def test_missing_core_after_start_still_recovers(self):self.assertEqual(self.run_case(True),(True,'1'))
 def test_manual_stop_never_recovers(self):self.assertEqual(self.run_case(True,True),(False,None))
