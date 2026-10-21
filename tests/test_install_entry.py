import hashlib, importlib.util, io, json, subprocess, sys, tarfile, tempfile, unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import build, prepare_offline, bootstrap
spec=importlib.util.spec_from_file_location('install_entry',ROOT/'start.py')
entry=importlib.util.module_from_spec(spec);spec.loader.exec_module(entry)

class InstallationEntry(unittest.TestCase):
 def test_online_bad_sha_never_launches_an_installer(self):
  with mock.patch.object(sys,'argv',['bootstrap.py','ax5','--router','192.168.1.1']),mock.patch.object(bootstrap.shutil,'which',return_value='/usr/bin/ssh'),mock.patch.object(bootstrap,'fetch',side_effect=[b'not an archive',('0'*64+'  shellcrash-router-panel-ax5-'+bootstrap.VERSION+'.tar.gz\n').encode()]),mock.patch.object(bootstrap.subprocess,'run')as run:
   with self.assertRaisesRegex(ValueError,'校验失败'):bootstrap.main()
   run.assert_not_called()
 def test_online_prepare_keeps_output_outside_temporary_download(self):
  name='shellcrash-router-panel-ax5-'+bootstrap.VERSION;stream=io.BytesIO()
  with tarfile.open(fileobj=stream,mode='w:gz')as tar:
   member=tarfile.TarInfo(name+'/tools/prepare_offline.py');member.size=0;tar.addfile(member,io.BytesIO())
  data=stream.getvalue();sums=(hashlib.sha256(data).hexdigest()+'  '+name+'.tar.gz\n').encode()
  with mock.patch.object(sys,'argv',['bootstrap.py','ax5','--prepare-offline']),mock.patch.object(bootstrap,'fetch',side_effect=[data,sums]),mock.patch.object(bootstrap.subprocess,'run',return_value=subprocess.CompletedProcess([],0))as run:
   self.assertEqual(bootstrap.main(),0);args=run.call_args.args[0];out=Path(args[args.index('--output')+1]);self.assertEqual(out.parent,Path.cwd());self.assertTrue(args[1].endswith('tools/prepare_offline.py'))
 def test_device_specific_dispatch_keeps_offline_inputs_and_update_separate(self):
  for profile,update in [('ax5',False),('k2p',False),('k2p',True)]:
   with tempfile.TemporaryDirectory()as td:
    root=build.build(profile,Path(td)/'package');nodes=Path(td)/'nodes.json';nodes.write_text('{}')
    args=['--router','192.168.1.1','--user','admin','--port','2222','--check-only']
    if update:args+=['--update']
    else:args+=['--offline','--core-file',str(ROOT/'vendor/ShellCrash-1.9.4.tar.gz'),'--nodes-file',str(nodes)]
    with mock.patch.object(entry,'ROOT',root),mock.patch.object(entry.shutil,'which',return_value='/usr/bin/ssh'),mock.patch.object(entry.subprocess,'run',return_value=subprocess.CompletedProcess([],0))as run:
     self.assertEqual(entry.main(args),0);cmd=run.call_args.args[0]
    self.assertTrue(cmd[1].endswith('update.py'if update else'deploy.py'))
    self.assertEqual(cmd[cmd.index('--port')+1],'2222');self.assertIn('--check-only',cmd)
    self.assertEqual('--core-file'in cmd,not update)
 def test_missing_offline_core_refuses_before_ssh_or_install(self):
  with tempfile.TemporaryDirectory()as td:
   root=build.build('ax5',td)
   with mock.patch.object(entry,'ROOT',root),mock.patch.object(entry.shutil,'which',return_value='/usr/bin/ssh'),mock.patch.object(entry.subprocess,'run')as run:
    with self.assertRaisesRegex(ValueError,'缺少'):entry.main(['--router','192.168.1.1','--offline'])
    run.assert_not_called()
 def test_prepare_does_not_require_ssh_or_contact_router(self):
  with tempfile.TemporaryDirectory()as td:
   root=build.build('ax5',td)
   with mock.patch.object(entry,'ROOT',root),mock.patch.object(entry.shutil,'which',return_value=None),mock.patch.object(entry.subprocess,'run',return_value=subprocess.CompletedProcess([],0))as run:
    self.assertEqual(entry.main(['--prepare-offline']),0)
    self.assertTrue(run.call_args.args[0][1].endswith('tools/prepare_offline.py'))
 def test_tampered_package_refuses_before_any_child_process(self):
  with tempfile.TemporaryDirectory()as td:
   root=build.build('k2p',td);(root/'install.sh').write_text('damaged')
   with mock.patch.object(entry,'ROOT',root),mock.patch.object(entry.subprocess,'run')as run:
    with self.assertRaises(ValueError):entry.main(['--router','192.168.1.1'])
    run.assert_not_called()
 def test_k2p_offline_install_without_node_file_does_not_fall_back_to_subscription(self):
  with tempfile.TemporaryDirectory()as td:
   root=build.build('k2p',td)
   with mock.patch.object(entry,'ROOT',root),mock.patch.object(entry.shutil,'which',return_value='/usr/bin/ssh'),mock.patch.object(entry.sys.stdin,'isatty',return_value=False),mock.patch.object(entry.subprocess,'run')as run:
    with self.assertRaises(SystemExit):entry.main(['--router','192.168.1.1','--offline','--core-file',str(ROOT/'vendor/ShellCrash-1.9.4.tar.gz')])
    run.assert_not_called()
 def test_packaged_offline_preparer_copies_only_manifest_files_and_validates_core(self):
  with tempfile.TemporaryDirectory()as td:
   root=build.build('ax5',Path(td)/'package');core=Path(td)/'core.tar.gz'
   with tarfile.open(core,'w:gz')as tar:
    member=tarfile.TarInfo('CrashCore');member.size=5;tar.addfile(member,io.BytesIO(b'core!'))
   descriptor=json.loads((root/'CORE.json').read_text());descriptor.update(sha256=hashlib.sha256(core.read_bytes()).hexdigest(),archive_size=core.stat().st_size);(root/'CORE.json').write_text(json.dumps(descriptor))
   rows=[]
   for line in(root/'MANIFEST.sha256').read_text().splitlines():
    _,name=line.split('  ',1);rows.append(hashlib.sha256((root/name).read_bytes()).hexdigest()+'  '+name+'\n')
   (root/'MANIFEST.sha256').write_text(''.join(rows));output=Path(td)/'offline'
   with mock.patch.object(prepare_offline,'ROOT',root),mock.patch.object(prepare_offline.urllib.request,'urlopen',side_effect=AssertionError('offline contacted network')):
    prepare_offline.prepare('ax5',core,output)
   import verify_package
   verify_package.verify(output);self.assertEqual((output/'core-offline.tar.gz').read_bytes(),core.read_bytes());self.assertTrue((output/'start.py').is_file());self.assertFalse((output/'dist').exists())
   with mock.patch.object(prepare_offline,'ROOT',root):
    with self.assertRaisesRegex(ValueError,'已存在'):prepare_offline.prepare('ax5',core,output)

if __name__=='__main__':unittest.main()
