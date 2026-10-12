#!/usr/bin/env python3
import hashlib, importlib.util, io, tempfile, unittest, subprocess, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('receiver', ROOT/'tools/mirror_receive.py');receiver=importlib.util.module_from_spec(spec);spec.loader.exec_module(receiver)
class MirrorTests(unittest.TestCase):
 def shell_env(self,p):
  import sys
  (p/'bin').mkdir()
  f=p/'bin/base64';f.write_text('#!'+sys.executable+'\nimport base64,sys\nsys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read() if sys.argv[-1] in ["-d","-D"] else open(sys.argv[-1],"rb").read()))\n');f.chmod(0o700)
  return dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def test_atomic_upload_and_blob_alias(self):
  with tempfile.TemporaryDirectory() as d:
   data=b'public-core-fixture';sha=hashlib.sha256(data).hexdigest();blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
   self.assertEqual(receiver.receive(d,'core '+sha,io.BytesIO(data)),sha)
   self.assertEqual((Path(d)/('blob-'+blob+'.tar.gz')).read_bytes(),data)
   meta=('version=1.12.13\nsha256='+sha+'\n').encode();h=hashlib.sha256(meta).hexdigest()
   receiver.receive(d,'info '+h,io.BytesIO(meta));self.assertEqual((Path(d)/'core-info.txt').read_bytes(),meta)
 def test_failed_upload_keeps_previous_metadata(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'core-info.txt').write_text('previous')
   for cmd,data in [('core '+'0'*64,b'wrong'),('../private '+'0'*64,b'x'),('info '+hashlib.sha256(b'bad').hexdigest(),b'bad')]:
    with self.assertRaises(ValueError):receiver.receive(d,cmd,io.BytesIO(data))
   self.assertEqual((p/'core-info.txt').read_text(),'previous');self.assertEqual(list(p.glob('.incoming-*')),[])
 def test_unconfigured_probe_makes_no_download_request(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'configs').mkdir();(p/'bin').mkdir();(p/'starts').mkdir();(p/'starts/remote.sh').write_bytes((ROOT/'payload/starts/remote.sh').read_bytes());(p/'starts/webdav.sh').write_bytes((ROOT/'payload/starts/webdav.sh').read_bytes());(p/'starts/remote-settings.sh').write_bytes((ROOT/'payload/starts/remote-settings.sh').read_bytes())
   stub=p/'bin/curl';stub.write_text('#!/bin/sh\ntouch "'+str(p/'unexpected-query')+'"\nexit 1\n');stub.chmod(0o700)
   result=subprocess.run(['sh','-c','C="$1"; D="$1"; . "$2"; mirror_probe', 'test', d, str(ROOT/'payload/starts/mirror_lib.sh')],env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH']),capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertFalse((p/'unexpected-query').exists())
   self.assertIn('"configured":false',(p/'mirror-check.json').read_text())
 def test_settings_validation_and_save_failure_restore(self):
  import base64
  def payload(url):
   return 'enabled=0\ntransport=webdav\nbase_b64='+base64.b64encode(url.encode()).decode()+'\nuser_b64=dGVzdA==\npassword_b64=c2VjcmV0\n'
  for url,save,expected in [('http://mirror.example.com/dav',0,0),('http://mirror.example.com/dav;id',0,1),('http://mirror.example.com/dav',1,1)]:
   with tempfile.TemporaryDirectory() as d:
    p=Path(d);(p/'configs').mkdir();(p/'starts').mkdir();(p/'job').mkdir()
    for name in ['mirror_lib.sh','remote.sh','webdav.sh','remote-settings.sh']:(p/'starts'/name).write_bytes((ROOT/'payload/starts'/name).read_bytes())
    before='enabled=0\nbase=http://old.example.com\ntarget=\n';(p/'configs/mirror.conf').write_text(before)
    (p/'job/kind').write_text('mirror');(p/'job/upload.parts').write_text('0000 '+base64.b64encode(payload(url).encode()).decode()+'\n')
    script='C="$1"; D="$1/job"; act=mirrorsave; phase(){ :; }; event(){ :; }; fail(){ :; }; save_safe(){ return '+str(save)+'; }; . "$2"'
    r=subprocess.run(['sh','-c',script,'test',d,str(ROOT/'payload/starts/mirror_update.sh')],env=self.shell_env(p),capture_output=True)
    self.assertEqual(r.returncode,expected,r.stderr+(p/"job/remote-save.error").read_bytes())
    self.assertFalse((p/'job/upload.parts').exists())
    if expected:
     self.assertEqual((p/'configs/mirror.conf').read_text(),before)
     self.assertIn('原设置' if save == 0 else '恢复原设置',(p/'job/remote-save.error').read_text())
    else:self.assertIn('transport=webdav',(p/'configs/mirror.conf').read_text())
 def test_size_limit_and_no_shell_commands(self):
  with tempfile.TemporaryDirectory() as d:
   data=b'x'*262145
   with self.assertRaises(ValueError):receiver.receive(d,'rules '+hashlib.sha256(data).hexdigest(),io.BytesIO(data))
   for command in ['sh','rules '+'0'*64+'; id','core ../../config.json','cn '+'A'*64]:
    with self.assertRaises(ValueError):receiver.receive(d,command,io.BytesIO(b''))
if __name__=='__main__':unittest.main(verbosity=2)
