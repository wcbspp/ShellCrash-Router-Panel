import json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class StatusJSON(unittest.TestCase):
 def test_transport_fields_do_not_break_status_json(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'C';d=p/'D';r=p/'R';b=p/'bin'
   for x in (c/'configs',c/'starts',d,r,b):x.mkdir(parents=True)
   (c/'version').write_text('1.9.4release\n')
   (c/'configs/ShellCrash.cfg').write_text('redir_mod=混合模式\n')
   (r/'transport-runtime').write_text('mixed\n')
   (c/'starts/panel_env.sh').write_text('PANEL_LAN_IP=192.168.1.1;PANEL_MAIN_GROUP=proxy-main\n')
   (c/'starts/resource_health.sh').write_text('resource_read(){ rh_warning_mb=20;rh_protect_mb=12;rh_cleanup_mb=20;rh_available=24576;rh_pressure=normal;rh_shmem=0;rh_slab=0;rh_tcp=0;rh_conn=0; }\n')
   (c/'starts/mirror_lib.sh').write_text('mirror_get(){ :; };remote_enabled(){ return 1; };remote_ready(){ return 1; };remote_transport(){ echo webdav; }\n')
   (c/'starts/transport_mode.sh').write_text('transport_configured(){ echo mixed; };transport_available(){ return 0; }\n')
   for name,code in [('pidof','echo 37'),('crontab','exit 1')]:
    f=b/name;f.write_text('#!/bin/sh\n'+code+'\n');f.chmod(0o700)
   f=p/'manage.sh';f.write_text((ROOT/'payload/starts/manage.sh').read_text().replace('/etc/storage/ShellCrash',str(c)).replace('/tmp/sc-admin',str(d)).replace('/tmp/ShellCrash',str(r)))
   q=subprocess.run(['sh',str(f),'status'],env={**os.environ,'PATH':str(b)+':'+os.environ['PATH']},capture_output=True,text=True)
   self.assertEqual(q.returncode,0,q.stderr);data=json.loads(q.stdout)
   self.assertEqual(data['pid'],37);self.assertEqual(data['transport'],{'configured':'mixed','active':'mixed','mixed_available':True});self.assertEqual(data['available_kb'],24576)
if __name__=='__main__':unittest.main()
