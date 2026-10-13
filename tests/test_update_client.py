import importlib.util,io,subprocess,sys,tarfile,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'));import build
spec=importlib.util.spec_from_file_location('pc_update',ROOT/'update.py');update=importlib.util.module_from_spec(spec);spec.loader.exec_module(update)
class UpdateClient(unittest.TestCase):
 def simulate(self,fail_backup=False):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);package=build.build('k2p',root/'package');calls=[];old=update.ROOT
   def run(argv,**kw):
    calls.append(argv);self.assertFalse(any('backup-app.sh' in x for x in argv))
    if argv[0]=='ssh' and kw.get('stdout') is not None and hasattr(kw['stdout'],'write'):
     if fail_backup:raise subprocess.CalledProcessError(1,argv)
     with tarfile.open(fileobj=kw['stdout'],mode='w:gz') as t:
      member=tarfile.TarInfo('./jsons/config.json');member.size=2;t.addfile(member,io.BytesIO(b'{}'))
    return subprocess.CompletedProcess(argv,0)
   try:
    update.ROOT=package
    with patch.object(sys,'argv',['update.py','--router','192.168.1.1','--backup-dir',str(root/'backup')]),patch.object(update.subprocess,'run',side_effect=run):
     if fail_backup:
      with self.assertRaises(subprocess.CalledProcessError):update.main()
     else:self.assertEqual(update.main(),0)
    commands=[argv[-1] for argv in calls if argv[0]=='ssh'];self.assertTrue(any('tar -czf - -C /etc/storage/ShellCrash .'==cmd for cmd in commands));self.assertEqual(any(cmd.endswith('/tools/update.sh --apply') for cmd in commands),not fail_backup)
    if not fail_backup:self.assertEqual(next((root/'backup').glob('*.tar.gz')).stat().st_mode&0o777,0o600)
   finally:update.ROOT=old
 def test_independent_snapshot_allows_exporter_repair(self):self.simulate()
 def test_failed_client_snapshot_never_applies_update(self):self.simulate(True)
if __name__=='__main__':unittest.main()
