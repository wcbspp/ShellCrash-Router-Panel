import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

class StartupSwitchTests(unittest.TestCase):
 def run_case(self, disabled, mode):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c=d/'persist';(c/'starts').mkdir(parents=True);bin=d/'bin';bin.mkdir()
   for name in ['legacy_storage_guard.sh','padavan_ui.sh','download_core.sh']:
    p=c/'starts'/name;p.write_text('#!/bin/sh\n'+('echo download >> "'+str(d/'calls')+'"\nexit 77\n' if name=='download_core.sh' else 'exit 0\n'));p.chmod(0o755)
   for name in ['sed','crontab','nvram']:
    p=bin/name;p.write_text('#!/bin/sh\nexit 0\n');p.chmod(0o755)
   if disabled:(c/'.dis_startup').touch()
   s=(ROOT/'payload/starts/panel_boot.sh').read_text().replace('/etc/storage/ShellCrash',str(c)).replace('/usr/sbin/nvram','nvram').replace('/proc/sys/vm/min_free_kbytes',str(d/'missing')).replace('/etc/profile',str(d/'profile'))
   f=d/'boot.sh';f.write_text(s)
   p=subprocess.run(['sh',str(f),mode],env=dict(os.environ,PATH=str(bin)+':'+os.environ['PATH']),capture_output=True,text=True)
   return p.returncode,(d/'calls').exists()
 def test_disabled_boot_never_downloads_or_starts(self):self.assertEqual(self.run_case(True,'boot'),(0,False))
 def test_enabled_boot_reaches_normal_bootstrap(self):self.assertEqual(self.run_case(False,'boot'),(1,True))
 def test_disabled_autostart_still_allows_manual_start(self):self.assertEqual(self.run_case(True,'manual'),(1,True))
