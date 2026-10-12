"""Recovery must use the installed hash; cloud/source status is never a boot prerequisite."""
import hashlib,io,os,subprocess,tarfile,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class RecoveryTests(unittest.TestCase):
 def fixture(self):
  td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup);d=Path(td.name);c=d/'persist';r=d/'ram';(c/'cache').mkdir(parents=True);r.mkdir();shim=d/'bin';shim.mkdir()
  good=d/'good.tar.gz'
  with tarfile.open(good,'w:gz') as t:
   body=b'fixture executable';m=tarfile.TarInfo('CrashCore');m.size=len(body);t.addfile(m,io.BytesIO(body))
  digest=hashlib.sha256(good.read_bytes()).hexdigest();(d/'bad').write_bytes(b'wrong-version')
  script=(ROOT/'ax5/recover-core.sh').read_text().replace('. /data/ShellCrash/ax5/core-env.sh','''C="%s";R="%s";HASH=%s;MIRROR=https://mirror.example.com;SOURCE=https://raw.githubusercontent.com/juewuy/ShellCrash/pinned/bin/meta/clash-linux-armv7.tar.gz'''%(c,r,digest))
  file=d/'recover.sh';file.write_text(script)
  curl=shim/'curl';curl.write_text('''#!/usr/bin/env python3
import sys,os,shutil
from pathlib import Path
a=sys.argv[1:];url=next(x for x in a if x.startswith('https://'));dest=a[a.index('-o')+1]
root=Path(os.environ['TEST_ROOT'])
with (root/'calls').open('a') as f:f.write(url+'\\n')
if os.environ.get('ALL_FAIL'):sys.exit(1)
shutil.copyfile(root/('bad' if 'mirror.example' in url else 'good.tar.gz'),dest)
''');curl.chmod(0o700)
  return d,c,r,file,dict(os.environ,PATH=str(shim)+os.pathsep+os.environ['PATH'],TEST_ROOT=str(d))
 def test_bad_mirror_hash_falls_back_to_native_source(self):
  d,c,r,p,env=self.fixture();result=subprocess.run(['sh',str(p)],env=env,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr);calls=(d/'calls').read_text().splitlines();self.assertIn('mirror.example',calls[0]);self.assertIn('jsdelivr.net/gh/juewuy/ShellCrash@pinned/',calls[1]);self.assertEqual((c/'cache/core-armv7.tar.gz').read_bytes(),(d/'good.tar.gz').read_bytes())
 def test_failed_recovery_does_not_touch_configuration(self):
  d,c,r,p,env=self.fixture();(c/'configs').mkdir();file=c/'configs/config.json';file.write_text('{"fixture":"preserved"}');env['ALL_FAIL']='1';result=subprocess.run(['sh',str(p)],env=env,capture_output=True,text=True);self.assertNotEqual(result.returncode,0);self.assertEqual(file.read_text(),'{"fixture":"preserved"}');self.assertFalse((c/'cache/core-armv7.tar.gz').exists())
 def test_interrupted_tool_update_restores_without_service(self):
  d,c,r,p,env=self.fixture();tool=d/'tool';tool.mkdir();(tool/'version').write_text('broken');archive=c/'cache/tool-previous.tar.gz'
  with tarfile.open(archive,'w:gz') as t:
   body=b'1.9.4release\n';m=tarfile.TarInfo('version');m.size=len(body);t.addfile(m,io.BytesIO(body))
  (c/'cache/tool-update-pending').write_text('1.9.4release');script=(ROOT/'ax5/tool-recover.sh').read_text().replace('/data/ShellCrash-tool',str(tool)).replace('/data/ShellCrash',str(c));f=d/'restore.sh';f.write_text(script)
  result=subprocess.run(['sh',str(f)],capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((tool/'version').read_text(),'1.9.4release\n');self.assertFalse((c/'cache/tool-update-pending').exists())
if __name__=='__main__':unittest.main()
