import base64,gzip,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class StagingTests(unittest.TestCase):
 def test_missing_download_never_stops_running_proxy(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);c=p/'persist';d=p/'admin';r=p/'ram';b=p/'bin'
   for x in [c/'starts',c/'configs',c/'jsons',d,r,b]:x.mkdir(parents=True,exist_ok=True)
   (c/'starts/panel_env.sh').write_text('PANEL_LAN_IP=192.168.123.1\nPANEL_MAIN_GROUP=proxy-main\n')
   (c/'starts/resource_health.sh').write_text('resource_read(){ rh_pressure=normal; rh_available=40960; rh_protect_mb=12; }\n')
   (c/'starts/group_layout.awk').write_text((ROOT/'payload/starts/group_layout.awk').read_text())
   (c/'starts/config_core.sh').write_text((ROOT/'payload/starts/config_core.sh').read_text())
   (c/'starts/core_release.sh').write_text('release_get(){ echo 8388608; }\n')
   (c/'starts/download_core.sh').write_text('#!/bin/sh\nexit 1\n');(c/'starts/download_core.sh').chmod(0o700)
   marker=p/'stopped';(c/'start.sh').write_text('#!/bin/sh\ntouch '+str(marker)+'\n');(c/'start.sh').chmod(0o700)
   cfg='{"log":{},\n"outbounds":[],\n"route":{}}\n';(c/'jsons/config.json').write_text(cfg);(c/'configs/subscription.url.b64').write_text('fixture')
   (d/'id').write_text('aabbccdd');(d/'kind').write_text('bounds');(d/'upload.parts').write_text('0000 '+base64.b64encode(gzip.compress(b'[{"type":"selector","tag":"proxy-main","outbounds":["node"]},{"type":"ss","tag":"node","server":"example.com"}]')).decode()+'\n')
   (b/'pidof').write_text('#!/bin/sh\necho 7\n');(b/'pidof').chmod(0o700)
   (b/'stat').write_text('#!/usr/bin/env python3\nimport os,sys\nprint(os.stat(sys.argv[-1]).st_size)\n');(b/'stat').chmod(0o700)
   (b/'base64').write_text('#!/usr/bin/env python3\nimport base64,sys\nargs=sys.argv[1:]\ndata=open(args[-1],"rb").read() if args and not args[-1].startswith("-") else sys.stdin.buffer.read()\nsys.stdout.buffer.write(base64.b64decode(data) if "-d" in args else base64.b64encode(data)+b"\\n")\n');(b/'base64').chmod(0o700)
   s=(ROOT/'payload/starts/manage.sh').read_text().replace('/etc/storage/ShellCrash',str(c)).replace('/tmp/sc-admin',str(d)).replace('/tmp/ShellCrash',str(r));f=p/'manage.sh';f.write_text(s)
   result=subprocess.run(['sh',str(f),'apply','aabbccdd'],env=dict(os.environ,SC_PROC_ROOT=str(p/'proc'),PATH=str(b)+os.pathsep+os.environ['PATH']),capture_output=True,text=True)
   self.assertNotEqual(result.returncode,0,result.stderr);self.assertFalse(marker.exists());self.assertEqual((c/'jsons/config.json').read_text(),cfg);self.assertEqual((d/'message').read_text().strip(),'core_download_failed')
if __name__=='__main__':unittest.main()
