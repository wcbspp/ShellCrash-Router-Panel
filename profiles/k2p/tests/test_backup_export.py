import base64,gzip,hashlib,os,subprocess,tarfile,tempfile,unittest
from pathlib import Path
SOURCE=Path(__file__).resolve().parents[1]/'payload/starts/backup-app.sh'
class BackupExport(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.c=self.root/'persist';self.d=self.root/'ram';self.d.mkdir();(self.c/'starts').mkdir(parents=True);(self.c/'configs').mkdir();(self.c/'ui').mkdir()
  (self.c/'starts/remote.sh').write_text('remote_ready(){ :; }\n')
  (self.c/'configs/core-installed.info').write_text('version=1.12.13\nsha256='+('1'*64)+'\n')
  (self.c/'configs/webdav.auth').write_text('private fixture');(self.c/'configs/webdav.user').write_text('user')
  (self.c/'configs/config-fixture.json').write_text('{"fixture":"keep"}')
  (self.c/'ui/fixture').write_bytes(b'A'*300000)
  self.mem=self.root/'meminfo';self.mem.write_text('MemAvailable: 13500 kB\n')
  self.lock=self.root/'save.lock';source=SOURCE.read_text().replace('C=/etc/storage/ShellCrash','C='+str(self.c)).replace('D=/tmp/sc-admin','D='+str(self.d)).replace('/proc/meminfo',str(self.mem)).replace('/tmp/shellcrash-storage-save.lock',str(self.lock)).replace('/etc/storage/.sc-backup-stage.',str(self.root/' .sc-backup-stage.').replace('/ .','/.'))
  self.script=self.root/'backup.sh';self.script.write_text(source)
  (self.root/'bin').mkdir();stub=self.root/'bin/sha256sum';stub.write_text('#!/usr/bin/env python3\nimport sys,hashlib\np=sys.argv[1];print(hashlib.sha256(open(p,"rb").read()).hexdigest()+"  "+p)\n');stub.chmod(0o700)
  self.env=dict(os.environ,PATH=str(self.root/'bin')+':'+os.environ['PATH'])
 def tearDown(self):self.tmp.cleanup()
 def run_backup(self):return subprocess.run(['sh',str(self.script),'local'],env=self.env,capture_output=True,timeout=30)
 def clean(self):
  self.assertFalse(self.lock.exists());self.assertEqual(list(self.root.glob('.sc-backup-stage.*')),[]);self.assertFalse((self.d/'application-backup.tar.gz.new').exists())
 def test_low_memory_snapshot_export_is_complete_and_does_not_modify_source(self):
  before=(self.c/'configs/webdav.auth').read_bytes();result=self.run_backup();self.assertEqual(result.returncode,0,result.stderr)
  self.clean();self.assertEqual((self.c/'configs/webdav.auth').read_bytes(),before);self.assertEqual((self.c/'configs/config-fixture.json').stat().st_nlink,1)
  b=(self.d/'application-backup.tar.gz').read_bytes();gzip.decompress(b)
  with tarfile.open(self.d/'application-backup.tar.gz')as t:
   names=t.getnames();self.assertIn('./RESTORE.txt',names);self.assertIn('./backup.info',names);self.assertNotIn('./configs/webdav.auth',names)
  header,encoded=(self.d/'backup-download.txt').read_text().split('\n',1);self.assertEqual(header,'SCBACKUP1 '+str(len(b))+' '+hashlib.sha256(b).hexdigest());self.assertEqual(base64.b64decode(encoded),b)
 def test_protection_and_failed_bounded_archive_keep_previous_backup(self):
  old=b'previous backup';(self.d/'application-backup.tar.gz').write_bytes(old)
  self.mem.write_text('MemAvailable: 12500 kB\n');self.assertNotEqual(self.run_backup().returncode,0);self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old);self.clean()
  self.mem.write_text('MemAvailable: 12801 kB\n');(self.c/'ui/fixture').write_bytes(os.urandom(600000));self.assertNotEqual(self.run_backup().returncode,0);self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old);self.clean()
 def test_existing_storage_commit_is_not_interrupted(self):
  self.lock.mkdir();self.assertNotEqual(self.run_backup().returncode,0);self.assertTrue(self.lock.exists());self.assertEqual(list(self.root.glob('.sc-backup-stage.*')),[])
