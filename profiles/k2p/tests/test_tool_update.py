"""Exercise release replacement and rejection with an isolated filesystem/network."""
import hashlib,io,os,shutil,subprocess,tarfile,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class ToolUpdateTests(unittest.TestCase):
 def fixture(self,version='1.9.5release',changed_guard=False,link=False,fail_save=False):
  td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup);d=Path(td.name);target=d/'tool';shutil.copytree(ROOT/'vendor/ShellCrash-1.9.4',target)
  (target/'configs').mkdir(exist_ok=True);(target/'configs/ShellCrash.cfg').write_text('')
  (target/'version').write_text('1.9.4release\n');(target/'starts/tool-guards.list').write_text(hashlib.sha256((target/'libs/core_tools.sh').read_bytes()).hexdigest()+'  libs/core_tools.sh\n')
  (target/'starts/save_storage.sh').write_text('#!/bin/sh\nexit '+('1' if fail_save else '0')+'\n');(target/'starts/save_storage.sh').chmod(0o700)
  upstream=d/'upstream';shutil.copytree(ROOT/'vendor/ShellCrash-1.9.4',upstream);(upstream/'version').write_text(version+'\n');(upstream/'menu.sh').write_text((upstream/'menu.sh').read_text()+'\n# fixture upstream change\n')
  if changed_guard:(upstream/'libs/core_tools.sh').write_text('#!/bin/sh\n# incompatible upstream\n')
  package=d/'package.tar.gz'
  with tarfile.open(package,'w:gz') as t:
   for p in upstream.rglob('*'):t.add(p,arcname=str(p.relative_to(upstream)),recursive=False)
   if link:
    member=tarfile.TarInfo('unsafe');member.type=tarfile.SYMTYPE;member.linkname='/etc/passwd';t.addfile(member)
  (d/'version').write_text(version+'\n')
  shim=d/'bin';shim.mkdir()
  curl=shim/'curl';curl.write_text('#!/usr/bin/env python3\nimport sys,shutil\nfrom pathlib import Path\na=sys.argv[1:];dest=a[a.index("-o")+1];url=next(x for x in a if x.startswith("https://"));shutil.copyfile("'+str(d)+'"+("/version" if url.endswith("/version") else "/package.tar.gz"),dest)\n');curl.chmod(0o700)
  for name in ['ps','pidof']:
   p=shim/name;p.write_text('#!/bin/sh\nexit 0\n');p.chmod(0o700)
  # No calls to init/start, network control, or service commands are permitted.
  for name in ['service','systemctl','reboot']:
   p=shim/name;p.write_text('#!/bin/sh\necho unexpected-service >&2;exit 99\n');p.chmod(0o700)
  script=(ROOT/'payload/starts/tool_update.sh').read_text().replace('/etc/storage/ShellCrash',str(target)).replace('/tmp/sc-admin',str(d/'runtime'))
  p=d/'update.sh';p.write_text(script)
  env=dict(os.environ,PATH=str(shim)+os.pathsep+os.environ['PATH'])
  return d,target,p,env
 def execute(self,p,env,mode='update'):return subprocess.run(['sh',str(p),'k2p',mode],env=env,capture_output=True,text=True)
 def test_release_updates_without_service_restart(self):
  d,t,p,env=self.fixture();result=self.execute(p,env);self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((t/'version').read_text().strip(),'1.9.5release');self.assertIn('fixture upstream change',(t/'menu.sh').read_text());self.assertIn('proxy and other services were not restarted',result.stdout);self.assertFalse((d/'runtime/operation.lock').exists())
 def test_beta_and_downgrade_rejected(self):
  for version in ['1.9.5beta3','1.8.9release']:
   d,t,p,env=self.fixture(version=version);result=self.execute(p,env);self.assertNotEqual(result.returncode,0);self.assertEqual((t/'version').read_text().strip(),'1.9.4release')
 def test_changed_adapter_dependency_rejected(self):
  d,t,p,env=self.fixture(changed_guard=True);result=self.execute(p,env);self.assertNotEqual(result.returncode,0);self.assertIn('compatibility check failed',result.stderr);self.assertEqual((t/'version').read_text().strip(),'1.9.4release')
 def test_archive_links_rejected(self):
  d,t,p,env=self.fixture(link=True);result=self.execute(p,env);self.assertNotEqual(result.returncode,0);self.assertEqual((t/'version').read_text().strip(),'1.9.4release');self.assertFalse((t/'unsafe').exists())
 def test_persistent_save_failure_restores_files(self):
  d,t,p,env=self.fixture(fail_save=True);before=(t/'menu.sh').read_bytes();result=self.execute(p,env);self.assertNotEqual(result.returncode,0);self.assertEqual((t/'version').read_text().strip(),'1.9.4release');self.assertEqual((t/'menu.sh').read_bytes(),before)
 def test_same_version_is_noop(self):
  d,t,p,env=self.fixture(version='1.9.4release');before=(t/'menu.sh').read_bytes();result=self.execute(p,env);self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((t/'menu.sh').read_bytes(),before);self.assertIn('service unchanged',result.stdout)
if __name__=='__main__':unittest.main()
