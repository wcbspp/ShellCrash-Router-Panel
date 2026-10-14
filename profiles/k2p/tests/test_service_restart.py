"""Restart must hold the verified tmpfs executable before stopping the process."""
import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class ServiceRestart(unittest.TestCase):
 def run_action(self,act,fail=False):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'configs').mkdir();(p/'starts').mkdir()
   (p/'starts/resource_health.sh').write_text('')
   (p/'starts/config_core.sh').write_text('configuration_core_prepare(){ echo prepare;[ "$PREPARE_FAIL" != 1 ]; }\n')
   text=(ROOT/'payload/starts/manage.sh').read_text();body=text.split(' start|stop|restart)\n',1)[1].split(';;\n apply)',1)[0]
   script='C="$1";D="$1";act="$2";lock(){ :; };phase(){ :; };event(){ :; };fail(){ echo failure; };pidof(){ [ "$STOPPED" != 1 ] && echo 37; };stop_core(){ echo stop; STOPPED=1; };start_core(){ echo start; };save_safe(){ echo save; };\n'+body
   return subprocess.run(['sh','-c',script,'test',str(p),act],capture_output=True,text=True,env={**os.environ,'PREPARE_FAIL':'1' if fail else '0'})
 def test_restart_prepares_before_stop_and_starts_once(self):
  r=self.run_action('restart');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout.splitlines(),['prepare','stop','start','save'])
 def test_failed_preparation_keeps_running_core(self):
  r=self.run_action('restart',True);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout.strip(),'prepare')
 def test_start_on_running_core_does_not_stage_or_stop(self):
  r=self.run_action('start');self.assertEqual(r.returncode,0);self.assertEqual(r.stdout.strip(),'save')
if __name__=='__main__':unittest.main()
