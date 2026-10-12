import hashlib,json,importlib.util,io,subprocess,sys,tarfile,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('computer_deploy',ROOT/'deploy.py');deploy=importlib.util.module_from_spec(spec);spec.loader.exec_module(deploy)
sys.path.insert(0,str(ROOT/'tools'));import build

class DeployTests(unittest.TestCase):
 def simulate(self,profile,args,fail_install=False):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);package=build.build(profile,root/'package');backup=root/'backup';calls=[]
   def fake_run(argv,**kw):
    calls.append(argv)
    if argv[0]=='ssh' and kw.get('stdout') is not None and hasattr(kw['stdout'],'write'):
     with tarfile.open(fileobj=kw['stdout'],mode='w:gz') as t:
      i=tarfile.TarInfo('fixture-config');i.size=2;t.addfile(i,io.BytesIO(b'{}'))
    if fail_install and argv[0]=='ssh' and argv[-1].endswith('sh install.sh auto'):raise subprocess.CalledProcessError(1,argv)
    return subprocess.CompletedProcess(argv,0)
   old=deploy.ROOT
   try:
    deploy.ROOT=package
    with patch.object(sys,'argv',['deploy.py','--router','192.168.1.1','--backup-dir',str(backup),*args]),patch.object(deploy.subprocess,'run',side_effect=fake_run):
     result=deploy.main()
    return result,calls,list(backup.glob('*.tar.gz'))
   finally:deploy.ROOT=old
 def test_ax5_check_does_not_install_or_backup(self):
  result,calls,backups=self.simulate('ax5',['--check-only']);self.assertEqual(result,0);self.assertFalse(backups)
  commands=[x[-1] for x in calls if x[0]=='ssh'];self.assertTrue(any(x.endswith('sh install.sh --check') for x in commands));self.assertFalse(any(x.endswith('sh install.sh auto') for x in commands))
  self.assertTrue(any(x.startswith('rm -rf /tmp/sc-ax5-') for x in commands))
 def test_ax5_install_checks_then_backs_up_then_installs(self):
  result,calls,backups=self.simulate('ax5',[]);self.assertEqual(result,0);self.assertEqual(len(backups),1)
  commands=[x[-1] for x in calls if x[0]=='ssh'];check=next(i for i,x in enumerate(commands) if x.endswith('sh install.sh --check'));backup=next(i for i,x in enumerate(commands) if 'set --;' in x);install=next(i for i,x in enumerate(commands) if x.endswith('sh install.sh auto'));self.assertLess(check,backup);self.assertLess(backup,install)
 def test_ax5_install_failure_still_closes_connection(self):
  with self.assertRaises(subprocess.CalledProcessError):self.simulate('ax5',[],True)
 def test_k2p_delegates_check_and_port(self):
  result,calls,_=self.simulate('k2p',['--check-only','--port','224']);self.assertEqual(result,0);self.assertEqual(len(calls),1)
  self.assertIn('--check-only',calls[-1]);self.assertIn('224',calls[-1]);self.assertTrue(calls[-1][1].endswith('tools/deploy.py'))
 def test_username_injection_never_reaches_ssh(self):
  with self.assertRaises(ValueError):self.simulate('ax5',['--user','root;echo bad'])
 def test_bad_core_rejects_before_ssh(self):
  with tempfile.TemporaryDirectory() as td:
   file=Path(td)/'bad-core.tgz';file.write_bytes(b'invalid')
   with self.assertRaises(ValueError):self.simulate('ax5',['--core-file',str(file)])
 def test_offline_core_is_transferred_once(self):
  with tempfile.TemporaryDirectory() as td:
   root=build.build('ax5',Path(td)/'package');core=root/'core-offline.tar.gz'
   with tarfile.open(core,'w:gz') as t:
    member=tarfile.TarInfo('CrashCore');member.size=2;t.addfile(member,io.BytesIO(b'OK'))
   info=json.loads((root/'CORE.json').read_text());info.update(archive_size=core.stat().st_size,sha256=hashlib.sha256(core.read_bytes()).hexdigest());(root/'CORE.json').write_text(json.dumps(info))
   files=sorted(p for p in root.rglob('*') if p.is_file() and p.name!='MANIFEST.sha256')
   (root/'MANIFEST.sha256').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n' for p in files))
   transfers=[]
   def run(argv,**kw):
    if 'input' in kw:
     with tarfile.open(fileobj=io.BytesIO(kw['input']),mode='r:gz') as t:transfers.extend(t.getnames())
    return subprocess.CompletedProcess(argv,0)
   old=deploy.ROOT
   try:
    deploy.ROOT=root
    with patch.object(sys,'argv',['deploy.py','--router','192.168.1.1','--check-only','--core-file',str(core),'--backup-dir',str(Path(td)/'backup')]),patch.object(deploy.subprocess,'run',side_effect=run):self.assertEqual(deploy.main(),0)
    self.assertEqual([name for name in transfers if name.endswith('core-offline.tar.gz')],['core-offline.tar.gz'])
   finally:deploy.ROOT=old
 def test_wrong_offline_path_rejects(self):
  with self.assertRaises(SystemExit):self.simulate('ax5',['--core-file','/nonexistent/core.tgz'])
if __name__=='__main__':unittest.main()
