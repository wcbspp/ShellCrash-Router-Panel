import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BackupBudget(unittest.TestCase):
 def test_rejection_keeps_old_archive_and_reports_actual_budget(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'C';d=p/'D';(c/'ax5').mkdir(parents=True);d.mkdir()
   (c/'ax5/remote.sh').write_text('')
   (d/'application-backup.tar.gz').write_bytes(b'previous')
   (d/'backup-error').write_text('stale failure')
   mem=p/'meminfo';mem.write_text('MemAvailable: 2048 kB\n')
   text=(ROOT/'ax5/backup-app.sh').read_text().replace('C=/data/ShellCrash','C='+str(c)).replace('D=/tmp/ShellCrash','D='+str(d)).replace('/proc/meminfo',str(mem)).replace('/data/ShellCrash-tool',str(c/'tool'))
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
   text=(ROOT/'ax5/dashboard-install.sh').read_text().replace('/proc/meminfo',str(mem)).replace('/tmp/ShellCrash',str(p/'runtime'))
   script=p/'dashboard.sh';script.write_text(text)
   result=subprocess.run(['sh',str(script),str(p/'C'),'meta'],capture_output=True,text=True)
   self.assertEqual(result.returncode,1)
   self.assertIn('可用 2048 KB',result.stdout)
   self.assertIn('20000 KB',result.stdout)
   self.assertTrue((p/'runtime/dashboard-error').is_file())
   self.assertFalse((p/'runtime-dashboard').exists())
