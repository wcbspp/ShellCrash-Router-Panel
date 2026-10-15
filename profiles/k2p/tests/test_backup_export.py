import base64,gzip,hashlib,os,subprocess,tarfile,tempfile,unittest
from pathlib import Path
SOURCE=Path(__file__).resolve().parents[1]/'payload/starts/backup-app.sh'
class BackupExport(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.c=self.root/'persist';self.d=self.root/'ram';self.d.mkdir();(self.c/'starts').mkdir(parents=True);(self.c/'configs').mkdir();(self.c/'ui').mkdir()
  link_source=SOURCE.parent/'backup-links.sh'
  if not link_source.exists():link_source=Path(__file__).resolve().parents[3]/'shared/lib/backup-links.sh'
  (self.c/'starts/backup-links.sh').write_bytes(link_source.read_bytes())
  (self.c/'starts/backup-guide.sh').write_bytes((SOURCE.parent/'backup-guide.sh').read_bytes())
  (self.c/'starts/resource_health.sh').write_bytes((SOURCE.parent/'resource_health.sh').read_bytes())
  (self.c/'starts/remote.sh').write_text('remote_ready(){ :; }\n')
  (self.c/'configs/core-installed.info').write_text('version=1.12.13\nsha256='+('1'*64)+'\n')
  (self.c/'configs/webdav.auth').write_text('private fixture');(self.c/'configs/webdav.user').write_text('user')
  (self.c/'configs/config-fixture.json').write_text('{"fixture":"keep"}')
  (self.c/'ui/fixture').write_bytes(b'A'*300000)
  (self.c/'servers.list').write_text('fixture server list');(self.c/'task.list').write_text('fixture task list')
  (self.c/'menus').mkdir();(self.c/'menus/bot_tg_service.sh').write_text('fixture menu');(self.c/'task').mkdir();(self.c/'task/afstart').write_text('fixture task')
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
   info=t.extractfile('./backup.info').read().decode();self.assertIn('autostart=1\n',info);self.assertIn('enabled=1\n',info);self.assertIn('traffic_mode=rule\n',info);self.assertIn('./servers.list',names);self.assertIn('./task.list',names);self.assertIn('./menus/bot_tg_service.sh',names);self.assertIn('./task/afstart',names)
  header,encoded=(self.d/'backup-download.txt').read_text().split('\n',1);self.assertEqual(header,'SCBACKUP1 '+str(len(b))+' '+hashlib.sha256(b).hexdigest());self.assertEqual(base64.b64decode(encoded),b)
 def test_protection_and_failed_bounded_archive_keep_previous_backup(self):
  old=b'previous backup';(self.d/'application-backup.tar.gz').write_bytes(old)
  self.mem.write_text('MemAvailable: 12500 kB\n');self.assertNotEqual(self.run_backup().returncode,0);self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old);self.clean()
  self.mem.write_text('MemAvailable: 12801 kB\n');(self.c/'ui/fixture').write_bytes(os.urandom(600000));self.assertNotEqual(self.run_backup().returncode,0);self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old);self.clean()
 def test_runtime_links_are_omitted_without_changing_live_aliases(self):
  (self.c/'jsons').mkdir();link=self.c/'jsons/dns.json';link.symlink_to('/tmp/panel-dns/dns.json')
  result=self.run_backup();self.assertEqual(result.returncode,0,result.stderr);self.assertTrue(link.is_symlink());self.clean()
  with tarfile.open(self.d/'application-backup.tar.gz') as t:
   self.assertNotIn('./jsons/dns.json',t.getnames());self.assertTrue(all(m.isfile() or m.isdir() for m in t.getmembers()))
 def test_unknown_link_rejects_and_keeps_previous_export(self):
  old=b'previous backup';(self.d/'application-backup.tar.gz').write_bytes(old);(self.c/'configs/unexpected').symlink_to('/etc/passwd')
  result=self.run_backup();self.assertNotEqual(result.returncode,0);self.assertIn('未知软链接',result.stderr.decode());self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old);self.clean()
 def test_existing_storage_commit_is_not_interrupted(self):
  self.lock.mkdir();self.assertNotEqual(self.run_backup().returncode,0);self.assertTrue(self.lock.exists());self.assertEqual(list(self.root.glob('.sc-backup-stage.*')),[])

 def test_custom_protection_floor_rejects_before_storage_lock(self):
  (self.c/'configs/memory.conf').write_text('warning_mb=20\nprotect_mb=14\ncleanup_mb=0\n')
  self.mem.write_text('MemAvailable: 14000 kB\n');old=b'previous';(self.d/'application-backup.tar.gz').write_bytes(old)
  result=self.run_backup();self.assertNotEqual(result.returncode,0);self.clean()
  self.assertEqual((self.d/'application-backup.tar.gz').read_bytes(),old)
 def test_invalid_memory_settings_fail_closed(self):
  (self.c/'configs/memory.conf').write_text('protect_mb=1\n')
  result=self.run_backup();self.assertNotEqual(result.returncode,0);self.clean()
  self.assertIn('内存保护设置无效',result.stdout.decode())
