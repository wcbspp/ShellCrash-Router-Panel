import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class PadavanAdapter(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.r=Path(self.tmp.name)
  self.bin=self.r/'bin';self.bin.mkdir();self.home=self.r/'zt';self.home.mkdir();self.c=self.r/'panel';(self.c/'starts').mkdir(parents=True)
  (self.r/'ram').mkdir();(self.r/'proc/123').mkdir(parents=True)
  for tool in ['zerotier-one','zerotier-cli']:self.script(self.bin/tool,'exit 0\n')
  self.script(self.bin/'pidof','echo 123\n');self.script(self.bin/'sleep','exit 0\n')
  for f in ['identity.secret','identity.public']:(self.home/f).write_text('fixture-identity\n')
  (self.r/'proc/123/cmdline').write_bytes((str(self.bin/'zerotier-one')+'\0'+str(self.home)+'\0').encode())
  self.script(self.bin/'ip','''case "$*" in
'-o link show')echo '15: ztabc: <UP>';;
'-4 route show table all')echo '192.0.2.0/24 via 10.99.0.2 dev ztabc proto static metric 5000';;
'addr show dev ztabc')echo 'inet 10.99.0.1/16';;
*-4\ route\ replace*)echo "$*" >> "'''+str(self.r/'restored')+'''";;
esac
''')
  source=(ROOT/'profiles/k2p/payload/starts/zerotier-service.sh').read_text()
  source=source.replace('PATH=/usr/sbin:/usr/bin:/sbin:/bin','PATH='+str(self.bin)+':'+os.environ['PATH'])
  for a,b in [('/usr/bin/zerotier-one',str(self.bin/'zerotier-one')),('/usr/bin/zerotier-cli',str(self.bin/'zerotier-cli')),('/var/lib/zerotier-one',str(self.home)),('/etc/storage/ShellCrash',str(self.c)),('/tmp/sc-admin',str(self.r/'ram')),('/proc/',str(self.r/'proc')+'/')]:source=source.replace(a,b)
  # No test is allowed to signal a real process.
  source=source.replace('case "$1" in','kill(){ if [ "$1" = -0 ];then [ "$2" != 123 ];else echo "$*" >> "'+str(self.r/'signals')+'";fi; }\ncase "$1" in',1)
  self.helper=self.r/'helper.sh';self.helper.write_text(source)
 def script(self,p,s):p.write_text('#!/bin/sh\n'+s);p.chmod(0o700)
 def run_helper(self,mode):return subprocess.run(['sh',str(self.helper),mode],capture_output=True,timeout=8)
 def test_missing_identity_never_signals_service(self):
  (self.home/'identity.secret').unlink();self.assertNotEqual(self.run_helper('start').returncode,0);self.assertFalse((self.r/'signals').exists())
 def test_unexpected_process_arguments_never_signal_service(self):
  (self.r/'proc/123/cmdline').write_bytes(b'other-service\0other-home\0');self.assertNotEqual(self.run_helper('start').returncode,0);self.assertFalse((self.r/'signals').exists())
 def test_storage_busy_retry_is_bounded(self):
  called=self.r/'save-count';self.script(self.c/'starts/save_storage.sh','echo called >> "'+str(called)+'"\nexit 75\n')
  self.assertEqual(self.run_helper('save').returncode,75);self.assertEqual(len(called.read_text().splitlines()),4)
 def test_restart_restores_existing_routes_without_firmware_replay(self):
  result=self.run_helper('start');self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual((self.r/'signals').read_text().strip(),'123')
  self.assertEqual((self.r/'restored').read_text().strip(),'-4 route replace 192.0.2.0/24 via 10.99.0.2 dev ztabc proto static metric 5000')
  self.assertFalse((self.r/'ram/zerotier-routes-pending').exists())
