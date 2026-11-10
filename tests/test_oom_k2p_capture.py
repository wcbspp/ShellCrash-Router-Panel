import base64, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class K2POOMCapture(unittest.TestCase):
 def test_oom_capture_and_unknown_does_not_overwrite(self):
  with tempfile.TemporaryDirectory() as temp:
   d=Path(temp); (d/'admin').mkdir();(d/'tool/starts').mkdir(parents=True);(d/'bin').mkdir();(d/'proc').mkdir()
   (d/'tool/starts/panel_env.sh').write_text('PANEL_LAN_IP=127.0.0.1\n')
   # The fixture is executed directly; Ubuntu /bin/sh lacks the firmware's pipefail.
   helper=d/'tool/starts/oom-store.sh';helper.write_text((ROOT/'profiles/k2p/payload/starts/oom-store.sh').read_text().replace('#!/bin/sh','#!/usr/bin/env bash',1));helper.chmod(0o755)
   for name in ('meminfo','sockstat','buddyinfo','boot_id'):(d/'proc'/name).write_text(('fixture-'+name+'\n')*1000)
   (d/'admin/resources.csv').write_text(''.join(f'{n},2,42,100,200,300,400,500,600,700,800,9,10,11,12\n' for n in range(1441)))
   (d/'admin/memory.csv').write_text('1,2,42,100,200,0\n')
   for name,body in {'dmesg':'echo "Out of memory: Killed process ${OOM_PID:-42} (CrashCore) anon-rss:20kB file-rss:10kB"','sha256sum':'exec /usr/bin/shasum -a 256'}.items():
    p=d/'bin'/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
   source=(ROOT/'profiles/k2p/payload/starts/incident_record.sh').read_text().replace('/tmp/sc-admin',str(d/'admin')).replace('/tmp/syslog.log',str(d/'syslog')).replace('/proc/sys/kernel/random/boot_id',str(d/'proc/boot_id')).replace('/proc/net/sockstat',str(d/'proc/sockstat')).replace('/proc/meminfo',str(d/'proc/meminfo')).replace('/proc/buddyinfo',str(d/'proc/buddyinfo'))
   script=d/'test.sh';script.write_text(source)
   (d/'proc/uptime').write_text('12345.67 0\n')
   env={**os.environ,'SC_OOM_UPTIME_FILE':str(d/'proc/uptime'),'CRASHDIR':str(d/'tool'),'SC_OOM_RUNTIME':str(d/'admin'),'PATH':str(d/'bin')+':'+os.environ['PATH']}
   subprocess.run(['sh',str(script),'begin','42'],env=env,check=True)
   self.assertTrue((d/'admin/oom-queue.b64').exists());evidence=(d/'admin/oom-evidence.log').read_text();self.assertIn('Killed process 42',evidence);self.assertIn('1440,2,42,100,200',evidence)
   record=base64.b64decode((d/'admin/oom-queue.b64').read_text()).decode();self.assertIn('Killed process 42',record);self.assertIn('1440,2,42,100,200',record)
   subprocess.run(['sh',str(script),'begin','43'],env=env,check=True)
   self.assertEqual((d/'admin/oom-evidence.log').read_text(),evidence)
   subprocess.run(['sh',str(script),'begin','43'],env=dict(env,OOM_PID='43'),check=True)
   self.assertEqual(len((d/'admin/oom-queue.b64').read_text().splitlines()),2)
   self.assertIn('Killed process 43',(d/'admin/oom-evidence.log').read_text())
