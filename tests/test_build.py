import hashlib,importlib.util,io,json,sys,tarfile,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
import build,bootstrap,verify_package,prepare_offline

class BuildTests(unittest.TestCase):
 def test_k2p_stream_upgrade_runtime_is_packaged(self):
  with tempfile.TemporaryDirectory() as td:
   target=build.build('k2p',td)
   for name in ('core_stream.lua','core_stream_extract.lua','core_http.lua'):
    self.assertEqual((target/'payload/starts'/name).read_bytes(),(ROOT/'profiles/k2p/payload/starts'/name).read_bytes())
   self.assertTrue((target/'tests/test_upgrade_helper_dispatch.py').is_file())
   verify_package.verify(target)
 def test_shared_source_roundtrip(self):
  for profile in build.PROFILES:
   with tempfile.TemporaryDirectory() as td:
    target=build.build(profile,td)
    manifest=json.loads((ROOT/'profiles'/profile/'manifest.json').read_text())
    golden=json.loads((ROOT/'profiles'/profile/'baseline.sha256.json').read_text())
    intentional=json.loads((ROOT/'profiles'/profile/'intentional_changes.json').read_text())
    for name,sha in golden.items():
     if intentional.get(name,{}).get('removed'):self.assertFalse((target/name).exists())
     else:self.assertEqual(hashlib.sha256((target/name).read_bytes()).hexdigest(),intentional.get(name,{}).get('sha256',sha),profile+'/'+name)
    verify_package.verify(target)
    methods=json.loads((ROOT/'profiles'/profile/'capabilities.json').read_text())['subscription_methods']
    self.assertEqual('convert' in methods,profile=='ax5')
 def test_build_refuses_private_unmanaged_files(self):
  with tempfile.TemporaryDirectory() as td:
   target=build.build('ax5',td);(target/'private-nodes.json').write_text('private-data')
   with self.assertRaises(ValueError):build.build('ax5',td)
 def test_bad_template_blocks_reject(self):
  for text in ['@@else@@\n','@@end@@\n','@@if other@@\n','@@if ax5@@\n','@@if ax5@@\n@@if k2p@@\n']:
   with self.assertRaises(ValueError):build.render(text,'ax5')
 def test_render_each_branch(self):
  text='common\n@@if ax5@@\nAX\n@@else@@\nK\n@@end@@\nend\n'
  self.assertEqual(build.render(text,'ax5'),'common\nAX\nend\n');self.assertEqual(build.render(text,'k2p'),'common\nK\nend\n')
 def test_package_mutation_and_extra_file(self):
  for mutation in ['damage','extra','remove']:
   with tempfile.TemporaryDirectory() as td:
    root=build.build('k2p',td)
    if mutation=='damage':(root/'install.sh').write_text('broken')
    elif mutation=='extra':(root/'extra').write_text('x')
    else:(root/'install.sh').unlink()
    with self.assertRaises((ValueError,OSError)):verify_package.verify(root)
 def test_local_inputs_do_not_exempt_declared_code(self):
  with tempfile.TemporaryDirectory() as td:
   root=build.build('k2p',td);node=root/'my-nodes.json';node.write_text('{}')
   verify_package.verify(root,[node]);(root/'install.sh').write_text('tampered')
   with self.assertRaises(ValueError):verify_package.verify(root,[node,root/'install.sh'])
 def test_archive_traversal_links_and_size_reject(self):
  for name,kind,size in [('pkg/../evil','file',1),('/pkg/file','file',1),('other/file','file',1),('pkg/link','link',0),('pkg/huge','file',21000000)]:
   with tempfile.TemporaryDirectory() as td:
    root=Path(td);archive=root/'x.tar.gz'
    with tarfile.open(archive,'w:gz') as t:
     info=tarfile.TarInfo(name)
     if kind=='link':info.type=tarfile.SYMTYPE;info.linkname='/etc/passwd';t.addfile(info)
     else:info.size=size;t.addfile(info,io.BytesIO(b'x'*size))
    with self.assertRaises(ValueError):bootstrap.extract(archive,root/'extract','pkg')
 def test_archive_good_extraction(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);archive=root/'x.tar.gz'
   with tarfile.open(archive,'w:gz') as t:
    i=tarfile.TarInfo('pkg/install.sh');i.size=2;t.addfile(i,io.BytesIO(b'ok'))
   self.assertEqual((bootstrap.extract(archive,root/'out','pkg')/'install.sh').read_bytes(),b'ok')
 def test_core_descriptor_matches_installer(self):
  ax=json.loads((ROOT/'profiles/ax5/core.json').read_text());self.assertIn(ax['sha256'],(ROOT/'profiles/ax5/install.sh').read_text());self.assertEqual(ax['sha256'],prepare_offline.core_spec('ax5')['sha256'])
  k=json.loads((ROOT/'profiles/k2p/core.json').read_text());self.assertEqual(k['sha256'],prepare_offline.core_spec('k2p')['sha256'])
 def test_core_has_wrong_architecture_hash(self):
  self.assertNotEqual(prepare_offline.core_spec('ax5')['sha256'],prepare_offline.core_spec('k2p')['sha256'])
 def test_core_archive_rejects_link_and_missing_executable(self):
  for name,link in [('CrashCore',True),('not-core',False)]:
   with tempfile.TemporaryDirectory() as td:
    archive=Path(td)/'core.tar.gz'
    with tarfile.open(archive,'w:gz') as t:
     i=tarfile.TarInfo(name)
     if link:i.type=tarfile.SYMTYPE;i.linkname='/bin/sh';t.addfile(i)
     else:i.size=1;t.addfile(i,io.BytesIO(b'x'))
    with self.assertRaises(ValueError):prepare_offline.validate_archive(archive)
if __name__=='__main__':unittest.main()
