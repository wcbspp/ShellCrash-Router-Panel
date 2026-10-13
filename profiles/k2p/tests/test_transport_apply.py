import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class TransportApply(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.p=Path(self.t.name)
  for d in ('configs','libs','starts','bin'):(self.p/d).mkdir()
  (self.p/'configs/ShellCrash.cfg').write_text('redir_mod=Redir模式\nother=keep\n')
  (self.p/'starts/resource_health.sh').write_text('resource_read(){ rh_pressure=${PRESSURE:-normal}; }\n')
  (self.p/'libs/set_config.sh').write_text('setconfig(){ grep -v "^$1=" "$C/configs/ShellCrash.cfg" > "$C/next";mv "$C/next" "$C/configs/ShellCrash.cfg";printf "%s=%s\\n" "$1" "$2" >> "$C/configs/ShellCrash.cfg"; }\n')
  (self.p/'libs/get_config.sh').write_text('')
  (self.p/'libs/web_save.sh').write_text('web_save(){ echo selection >> "$C/calls"; }\n')
  (self.p/'starts/traffic_mode.sh').write_text('traffic_mode_apply(){ echo flow-$1 >> "$C/calls"; }\n')
  f=self.p/'check';f.write_text('#!/bin/sh\nexit ${CHECK_FAIL:-0}\n');f.chmod(0o700)
  f=self.p/'bin/pidof';f.write_text('#!/bin/sh\n[ "$STOPPED" = 1 ] || echo 37\n');f.chmod(0o700)
  f=self.p/'bin/ip';f.write_text('#!/bin/sh\n[ "$CONFLICT" != 1 ] || echo occupied\n[ "$1" != link ]\n');f.chmod(0o700)
 def run_apply(self,mode,**env):
  script='''C="$1";D="$1";. "$2";
fail(){ echo error-$1 >> "$C/calls"; };phase(){ echo phase-$1 >> "$C/calls"; }
transport_available(){ [ "$NO_TUN" != 1 ]; };transport_ready(){ :; };transport_wait_ready(){ :; }
configuration_core_prepare(){ configuration_core_source="$C/check"; }
save_safe(){ echo save >> "$C/calls"; }
stop_core(){ echo stop >> "$C/calls"; }
start_core(){ echo start >> "$C/calls";[ "$START_FAIL" != 1 ] || [ "$(transport_configured)" = redir ]; }
transport_apply "$3"
'''
  return subprocess.run(['sh','-c',script,'fixture',str(self.p),str(ROOT/'payload/starts/transport_mode.sh'),mode],capture_output=True,text=True,env={**os.environ,'PATH':str(self.p/'bin')+':'+os.environ['PATH'],**env})
 def calls(self):return (self.p/'calls').read_text() if (self.p/'calls').exists() else ''
 def test_same_mode_never_restarts(self):
  self.assertEqual(self.run_apply('redir').returncode,0);self.assertNotIn('stop',self.calls())
 def test_mixed_calls_official_start_and_preserves_other_config(self):
  r=self.run_apply('mixed');self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual(self.calls().count('stop'),1);self.assertEqual(self.calls().count('start'),1)
  self.assertIn('other=keep', (self.p/'configs/ShellCrash.cfg').read_text());self.assertIn('selection',self.calls());self.assertIn('flow-rule',self.calls())
 def test_failed_start_restores_old_setting(self):
  r=self.run_apply('mixed',START_FAIL='1');self.assertNotEqual(r.returncode,0)
  self.assertIn('redir_mod=Redir模式',(self.p/'configs/ShellCrash.cfg').read_text());self.assertEqual(self.calls().count('stop'),2)
 def test_guard_and_capability_do_not_change_setting(self):
  for env in ({'PRESSURE':'protect'},{'NO_TUN':'1'},{'CHECK_FAIL':'1'},{'CONFLICT':'1'}):
   self.assertNotEqual(self.run_apply('mixed',**env).returncode,0);self.assertNotIn('stop',self.calls());self.assertIn('redir_mod=Redir模式',(self.p/'configs/ShellCrash.cfg').read_text())
 def test_stopped_save_does_not_start(self):
  self.assertEqual(self.run_apply('mixed',STOPPED='1').returncode,0);self.assertNotIn('start',self.calls());self.assertIn('redir_mod=混合模式',(self.p/'configs/ShellCrash.cfg').read_text())
 def test_invalid_mode_does_not_write(self):
  self.assertNotEqual(self.run_apply('bad').returncode,0);self.assertNotIn('save',self.calls());self.assertNotIn('stop',self.calls())
if __name__=='__main__':unittest.main()
