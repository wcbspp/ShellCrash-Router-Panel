import hashlib,io,re,subprocess,tarfile,tempfile,unittest,gzip,random,shlex
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class CompressedDashboard(unittest.TestCase):
 def run_fixture(self,body):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);p=Path(self.temp.name);c=p/'C';(c/'ax5').mkdir(parents=True);(c/'configs').mkdir();(c/'configs/ShellCrash.cfg').write_text('')
  archive=p/'source.tar.gz'
  with tarfile.open(archive,'w:gz') as tar:
   for name,raw in [('index.html',b'<html><head></head><body></body></html>'),('assets/app.js',body),('sw.js',b'ignored')]:
    info=tarfile.TarInfo(name);info.size=len(raw);tar.addfile(info,io.BytesIO(raw))
  expected=hashlib.sha256(archive.read_bytes()).hexdigest()
  (c/'ax5/remote.sh').write_text('remote_ready(){ return 1; }\nremote_transport(){ echo webdav; }\nremote_fetch(){ cp '+shlex.quote(str(archive))+' "$4"; }\n')
  (c/'ui').mkdir();(c/'ui/dashboard-bridge.js').write_text('/* fixture bridge */')
  mem=p/'meminfo';mem.write_text('MemAvailable: 17000 kB\n')
  script=(ROOT/'ax5/dashboard-install.sh').read_text().replace('05dccb1a756f8029cb2b7c70f90852390ae5cbe6093e888f1a9f68d3b122ee1e',expected)
  script=re.sub(r'^protect=\$\(lua.*$', 'protect=14',script,flags=re.M).replace('/proc/meminfo',str(mem)).replace('/tmp/ShellCrash',str(p/'runtime')).replace('/tmp/sc-dashboard',str(p/'dashboard'))
  (p/'script').write_text(script)
  return p,subprocess.run(['sh',str(p/'script'),str(c),'meta'],capture_output=True,text=True)
 def test_large_js_is_cached_compressed_below_budget(self):
  body=b'/*'+b'fixture '*260000+b'*/'
  p,result=self.run_fixture(body);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  self.assertEqual(gzip.decompress((p/'runtime-dashboard/assets/app.js.gz').read_bytes()),body)
  self.assertFalse((p/'runtime-dashboard/assets/app.js').exists());self.assertFalse((p/'runtime-dashboard/sw.js.gz').exists())
  self.assertIn('dashboard-bridge.js',(p/'runtime-dashboard/index.html').read_text())
  self.assertTrue((p/'runtime-dashboard/.ready').exists());self.assertFalse((p/'dashboard-stage').exists())
 def test_oversize_compressed_cache_is_rejected_and_cleaned(self):
  p,result=self.run_fixture(random.Random(1).randbytes(1100000));self.assertNotEqual(result.returncode,0)
  self.assertFalse((p/'runtime-dashboard/.ready').exists());self.assertFalse((p/'dashboard-stage').exists());self.assertFalse((p/'dashboard.tar.gz').exists())
