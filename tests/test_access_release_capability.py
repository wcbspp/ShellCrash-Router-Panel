"""Release packages must expose the reviewed feature without per-device markers."""
import importlib.util,re,subprocess,tempfile,unittest
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('release_build',ROOT/'tools/build.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
class AccessReleaseCapability(unittest.TestCase):
 def test_both_packages_ship_capability_without_user_policy(self):
  for profile,path in [('ax5','ax5/proxy-access-ready'),('k2p','payload/starts/proxy-access-ready')]:
   with tempfile.TemporaryDirectory() as td:
    package=builder.build(profile,td);self.assertEqual((package/path).read_bytes(),b'1\n');self.assertFalse((package/'configs/proxy-access').exists());self.assertFalse((package/'payload/configs/proxy-access').exists())
 def test_k_state_uses_shipped_capability_not_private_config(self):
  source=(ROOT/'profiles/k2p/payload/starts/manage.sh').read_text();line=next(x for x in source.splitlines()if 'acl_available=false;' in x)
  with tempfile.TemporaryDirectory() as td:
   c=Path(td);(c/'starts').mkdir();(c/'configs').mkdir();(c/'configs/proxy-access-verified').write_text('1\n')
   def state():return subprocess.check_output(['sh','-c','C="$1";'+line+';printf %s "$acl_available"','sh',td],stderr=subprocess.DEVNULL).decode()
   self.assertEqual(state(),'false');(c/'starts/proxy-access-ready').write_text('1\n');self.assertEqual(state(),'true');(c/'starts/proxy-access-ready').unlink();self.assertEqual(state(),'false')
  self.assertIn('cat "$C/starts/proxy-access-ready"',source.split(' access)',1)[1])
 def test_ax_state_gate_matches_job_gate(self):
  source=(ROOT/'profiles/ax5/ax5/common.lua').read_text();expression=re.search(r's\.proxy_access=\{available=(.*?),error=',source).group(1)
  lua=LuaRuntime();check=lua.eval('function(M)return '+expression+' end')
  with tempfile.TemporaryDirectory() as td:
   c=Path(td);(c/'ax5').mkdir();(c/'configs').mkdir();(c/'configs/proxy-access-verified').write_text('1\n');m=lua.table_from({'C':td,'read':lambda p:Path(p).read_text() if Path(p).exists()else''})
   self.assertFalse(check(m));(c/'ax5/proxy-access-ready').write_text('1\n');self.assertTrue(check(m));(c/'ax5/proxy-access-ready').write_text('0\n');self.assertFalse(check(m))
  self.assertIn("assert(M.read(M.C..'/ax5/proxy-access-ready')=='1\\n'",(ROOT/'profiles/ax5/ax5/job.lua').read_text())
