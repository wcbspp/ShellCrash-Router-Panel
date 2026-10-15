import os,subprocess,tempfile,unittest,tarfile,hashlib,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BackupBudget(unittest.TestCase):
 def fixture_source(self, protect=14):
  return re.sub(r'^protect=\$\(lua.*$', 'protect='+str(protect), (ROOT/'ax5/backup-app.sh').read_text(), flags=re.M)
 def test_custom_protection_floor_rejects_before_snapshot(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'C';d=p/'D';(c/'ax5').mkdir(parents=True);d.mkdir()
   (c/'ax5/remote.sh').write_text('');(d/'application-backup.tar.gz').write_bytes(b'previous')
   mem=p/'meminfo';mem.write_text('MemAvailable: 17000 kB\n')
   script=p/'backup.sh';script.write_text(self.fixture_source(18).replace('C=/data/ShellCrash','C='+str(c)).replace('D=/tmp/ShellCrash','D='+str(d)).replace('/proc/meminfo',str(mem)))
   result=subprocess.run(['sh',str(script),'local'],capture_output=True,text=True)
   self.assertEqual(result.returncode,1);self.assertIn('18944 KB',result.stdout)
   self.assertEqual((d/'application-backup.tar.gz').read_bytes(),b'previous');self.assertFalse(list(c.glob('.backup-stage.*')))

 def test_rejection_keeps_old_archive_and_reports_actual_budget(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'C';d=p/'D';(c/'ax5').mkdir(parents=True);d.mkdir()
   (c/'ax5/remote.sh').write_text('')
   (d/'application-backup.tar.gz').write_bytes(b'previous')
   (d/'backup-error').write_text('stale failure')
   mem=p/'meminfo';mem.write_text('MemAvailable: 2048 kB\n')
   text=self.fixture_source().replace('C=/data/ShellCrash','C='+str(c)).replace('D=/tmp/ShellCrash','D='+str(d)).replace('/proc/meminfo',str(mem)).replace('/data/ShellCrash-tool',str(c/'tool'))
   script=p/'backup.sh';script.write_text(text)
   result=subprocess.run(['sh',str(script),'local'],capture_output=True,text=True)
   self.assertEqual(result.returncode,1)
   self.assertIn('可用 2048 KB',result.stdout)
   self.assertIn('安全打包至少需要',result.stdout)
   self.assertNotIn('stale failure',(d/'backup-error').read_text())
   self.assertEqual((d/'application-backup.tar.gz').read_bytes(),b'previous')
   self.assertFalse((d/'backup-stage').exists())
 def test_dashboard_low_memory_is_explicit_without_download(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);mem=p/'meminfo';mem.write_text('MemAvailable: 2048 kB\n')
   text=re.sub(r'^protect=\$\(lua.*$', 'protect=14', (ROOT/'ax5/dashboard-install.sh').read_text(), flags=re.M).replace('/proc/meminfo',str(mem)).replace('/tmp/ShellCrash',str(p/'runtime'))
   script=p/'dashboard.sh';script.write_text(text)
   result=subprocess.run(['sh',str(script),str(p/'C'),'meta'],capture_output=True,text=True)
   self.assertEqual(result.returncode,1)
   self.assertIn('可用 2048 KB',result.stdout)
   self.assertIn('16896 KB',result.stdout)
   self.assertTrue((p/'runtime/dashboard-error').is_file())
   self.assertFalse((p/'runtime-dashboard').exists())
 def test_flash_hardlink_snapshot_exports_without_ram_file_copy(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'C';d=p/'D';tool=c/'tool'
   for folder in ['ax5','configs','ui','ruleset','cache','tool/configs']: (c/folder).mkdir(parents=True,exist_ok=True)
   d.mkdir();(c/'ax5/remote.sh').write_text('')
   (c/'ax5/core-env.sh').write_text('HASH=fixture\nVERSION=1\n')
   links=ROOT/'ax5/backup-links.sh'
   if not links.exists():links=ROOT.parents[1]/'shared/lib/backup-links.sh'
   (c/'ax5/backup-links.sh').write_bytes(links.read_bytes())
   (c/'ax5/backup-guide.sh').write_bytes((ROOT/'ax5/backup-guide.sh').read_bytes())
   (c/'cache/core.env').write_text('HASH=fixture\n')
   original=b'fixture-config'*20000;(c/'configs/config.json').write_bytes(original)
   (c/'configs/webdav.auth').write_text('excluded-fixture')
   (tool/'configs/command.env').write_text('runtime-only')
   mem=p/'meminfo';mem.write_text('MemAvailable: 17000 kB\n')
   text=self.fixture_source().replace('C=/data/ShellCrash','C='+str(c)).replace('D=/tmp/ShellCrash','D='+str(d)).replace('/proc/meminfo',str(mem)).replace('/data/ShellCrash-tool',str(tool))
   script=p/'backup.sh';script.write_text(text)
   result=subprocess.run(['sh',str(script),'local'],capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr+result.stdout)
   self.assertEqual((c/'configs/config.json').read_bytes(),original)
   self.assertTrue((c/'configs/webdav.auth').exists())
   self.assertFalse(list(c.glob('.backup-stage.*')))
   with tarfile.open(d/'application-backup.tar.gz','r:gz') as t:
    names={x.name for x in t.getmembers()}
    self.assertNotIn('./configs/webdav.auth',names);self.assertNotIn('./ShellCrash-tool/configs/command.env',names)
    self.assertEqual(t.extractfile('./configs/config.json').read(),original)
    self.assertIn(b'format=1',t.extractfile('./backup.info').read())
    self.assertFalse(any(x.issym() for x in t.getmembers()))
