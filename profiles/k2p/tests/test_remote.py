import hashlib, importlib.util, io, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('receiver', ROOT/'tools/remote_receive.py');r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class Remote(unittest.TestCase):
 def call(self, root, private, command, data=b''):
  out=io.BytesIO();r.transfer(root,private,command,io.BytesIO(data),out);return out.getvalue()
 def test_round_trip_private_and_public(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'public';private=Path(d)/'private'
   self.assertEqual(self.call(root,private,'probe'),b'SCMIRROR/2\n')
   for kind,ext in [('core','tar.gz'),('backup','tar.gz'),('cn','srs'),('cn','mrs'),('dashboard','tar.gz')]:
    data=kind.encode()+b'fixture';h=hashlib.sha256(data).hexdigest()
    self.assertEqual(self.call(root,private,f'put {kind} {h} {ext}',data),h.encode()+b'\n')
    self.assertEqual(self.call(root,private,f'get {kind} {h} {ext}'),data)
    self.assertEqual(self.call(root,private,f'stat {kind} {h} {ext}'),h.encode()+b'\n')
   self.assertFalse(list(root.glob('backup-*')))
   self.assertEqual(next(private.iterdir()).stat().st_mode&0o777,0o600)
 def test_rejection_keeps_current(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'public';private=Path(d)/'private';self.call(root,private,'probe')
   data=b'good';h=hashlib.sha256(data).hexdigest();self.call(root,private,f'put backup {h} tar.gz',data)
   for cmd,payload in [(f'put backup {h} tar.gz',b'bad'),('get backup ../../key tar.gz',b''),('rm -rf /',b''),(f'put probe {h} txt',b'x'*65)]:
    with self.assertRaises(ValueError):self.call(root,private,cmd,payload)
   self.assertEqual(self.call(root,private,f'get backup {h} tar.gz'),data);self.assertFalse(list(private.glob('.incoming-*')))
 def test_manifests_and_legacy_compatibility(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'public';private=Path(d)/'private';data=b'core';h=hashlib.sha256(data).hexdigest()
   self.call(root,private,'core '+h,data)
   for kind in ['core','meta','singbox']:
    text=(('' if kind=='core' else f'KIND={kind}\n')+f'VERSION=1.19.28\nHASH={h}\n').encode();sha=hashlib.sha256(text).hexdigest()
    self.call(root,private,f'put info {sha} txt',text)
    self.assertEqual(self.call(root,private,'manifest '+kind),text)
 def test_symlinks_and_private_subtree_refused(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);root=p/'public';private=p/'private';self.call(root,private,'probe')
   h='0'*64;(root/f'core-{h}.tar.gz').symlink_to('/etc/passwd')
   with self.assertRaises(ValueError):self.call(root,private,f'get core {h} tar.gz')
   with self.assertRaises(ValueError):self.call(root,root/'private','probe')
 def test_switch_and_changed_credentials_no_network(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'configs').mkdir();(p/'bin').mkdir()
   for directory in ['ax5','starts']:
    (p/directory).mkdir();(p/directory/'webdav.sh').write_bytes((ROOT/'payload/starts/webdav.sh').read_bytes())
   for name in ['mirror_key','mirror_known_hosts']:(p/'configs'/name).write_text('fixture')
   ssh=p/'bin/ssh';ssh.write_text('#!/bin/sh\ntouch "'+str(p/'unexpected')+'"\nexit 1\n');ssh.chmod(0o700)
   env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
   for enabled in ['0','1']:
    (p/'configs/mirror.conf').write_text(f'enabled={enabled}\nbase=\ntarget=fixture@server:22\n')
    script='C="$1"; D="$1"; . "$2"; remote_fetch core '+('0'*64)+' tar.gz "$1/file" 64'
    result=subprocess.run(['sh','-c',script,'test',d,str(ROOT/'payload/starts/remote.sh')],env=env,capture_output=True)
    self.assertEqual(result.returncode,2);self.assertFalse((p/'unexpected').exists());self.assertFalse((p/'file').exists())
if __name__=='__main__':unittest.main(verbosity=2)
