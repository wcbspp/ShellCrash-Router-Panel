import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

class BootReadinessTests(unittest.TestCase):
 def run_case(self, dispatch=0, ready_after=0, api=True, manual=False, mode_ok=True, previous_stop=False):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td); c=d/'persist'; (c/'configs').mkdir(parents=True); b=d/'bin'; b.mkdir()
   (c/'configs/ShellCrash.cfg').write_text('secret=fixture\n')
   (c/'start.sh').write_text(f'#!/bin/sh\necho dispatch-diagnostic >&2\necho ${{SC_PANEL_STARTING:-missing}} > "{d}/starting"\nexit {dispatch}\n'); (c/'start.sh').chmod(0o755)
   (d/'ram').mkdir(); (d/'clock').write_text('0')
   if previous_stop: (d/'ram/manual-stop').touch()
   commands={
    'cut':f'#!/bin/sh\ncat "{d}/clock"\n',
    'sleep':f'#!/bin/sh\nn=$(cat "{d}/clock"); echo $((n+30)) > "{d}/clock"\n'+(f'touch "{d}/ram/manual-stop"\n' if manual else ''),
    'pidof':f'#!/bin/sh\n[ $(cat "{d}/clock") -ge {ready_after} ] && echo 123\n',
    'curl':f'#!/bin/sh\ncase "$*" in *PATCH*)exit {0 if mode_ok else 1};;*)exit {0 if api else 1};;esac\n',
   }
   for name,text in commands.items(): (b/name).write_text(text); (b/name).chmod(0o755)
   source=(ROOT/'payload/starts/panel_boot.sh').read_text().split('native_result=0\n',1)[1]
   source='native_result=0\n'+source.replace('/tmp/ShellCrash',str(d/'ram')).replace('/tmp/sc-admin',str(d/'admin'))
   p=d/'readiness.sh'; p.write_text(source)
   result=subprocess.run(['sh',str(p)],env=dict(os.environ,CRASHDIR=str(c),PANEL_LAN_IP='127.0.0.1',PATH=str(b)+':'+os.environ['PATH']),capture_output=True,text=True,timeout=15)
   self.assertIn('dispatch-diagnostic',(d/'admin/service.log').read_text())
   self.assertEqual((d/'starting').read_text().strip(),'1')
   log=(d/'admin/events.log').read_text() if (d/'admin/events.log').exists() else ''
   return result.returncode, log
 def test_mode_reset_failure_is_not_reported_as_ready(self):
  code,log=self.run_case(mode_ok=False);self.assertEqual(code,1);self.assertIn('rule mode reset failed',log)
 def test_dispatch_zero_is_not_readiness(self):
  code,log=self.run_case(ready_after=1000); self.assertEqual(code,1); self.assertIn('dispatch exit 0',log)
 def test_nonzero_dispatch_with_live_api_is_success(self): self.assertEqual(self.run_case(dispatch=2),(0,''))
 def test_process_without_authenticated_api_is_failure(self): self.assertEqual(self.run_case(api=False)[0],1)
 def test_background_start_waits_until_ready(self): self.assertEqual(self.run_case(ready_after=60),(0,''))
 def test_manual_stop_during_boot_is_respected(self): self.assertEqual(self.run_case(manual=True,ready_after=1000),(0,''))
 def test_previous_stop_marker_waits_for_delayed_start(self): self.assertEqual(self.run_case(previous_stop=True,ready_after=60),(0,''))
 def test_previous_stop_marker_does_not_hide_start_timeout(self):
  code,log=self.run_case(previous_stop=True,ready_after=1000);self.assertEqual(code,1);self.assertIn('dispatch exit 0',log)

if __name__=='__main__': unittest.main()
