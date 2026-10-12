#!/usr/bin/env python3
"""Offline checks: never connect to a router or run its installer."""
import base64, importlib.util, io, json, os, re, shutil, subprocess, sys, tarfile, tempfile, unittest
from unittest.mock import patch
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def run(args,**kw):return subprocess.run(args,capture_output=True,text=True,errors="backslashreplace",**kw)

class ProjectTests(unittest.TestCase):
 def test_shell_syntax(self):
  for p in ROOT.rglob('*.sh'):
   result=run(['sh','-n',str(p)])
   self.assertEqual(result.returncode,0,f'{p.relative_to(ROOT)}: {result.stderr}')
 def test_javascript_syntax(self):
  if not shutil.which('node'):self.skipTest('Node.js unavailable')
  sources=[(str(p.relative_to(ROOT)),p.read_text()) for p in (ROOT/'payload/padavan').glob('*.js')]
  html=(ROOT/'payload/ui/index.html').read_text()
  sources += [('inline',s) for s in re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.S)]
  for label,source in sources:
   result=run(['node','--check','-'],input=source)
   self.assertEqual(result.returncode,0,f'{label}: {result.stderr}')
 def profile(self,nodes,cn='1.0.1.0/24\n'):
  td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup);d=Path(td.name)
  (d/'nodes.json').write_text(json.dumps({'outbounds':nodes}));(d/'cn.txt').write_text(cn)
  result=run([sys.executable,str(ROOT/'tools/prepare_profile.py'),'--input',str(d/'nodes.json'),'--output',str(d/'private.json'),'--lan-ip','192.168.1.1','--secret-file',str(d/'secret'),'--cn-list',str(d/'cn.txt')])
  return result,d
 def nodes(self):return [{'type':'anytls','tag':'香港01','server':'proxy.example.com','server_port':443,'password':'fixture-password','tls':{'enabled':True}}]
 def test_profile_groups_private_and_format(self):
  nodes=self.nodes()+[{'type':'trojan','tag':'台湾02','server':'other.example.com','server_port':443,'password':'fixture-only'}]
  result,d=self.profile(nodes);self.assertEqual(result.returncode,0,result.stderr)
  obj=json.loads((d/'private.json').read_text());secret=(d/'secret').read_text().strip()
  self.assertEqual(len(secret),48);self.assertNotIn(secret,result.stdout)
  self.assertEqual(obj['experimental']['clash_api']['secret'],secret)
  self.assertEqual(obj['outbounds'][0]['tag'],'proxy-main')
  self.assertEqual(obj['outbounds'][0]['outbounds'],['地区/香港','地区/台湾'])
  self.assertEqual(obj['outbounds'][-2:],nodes)
  self.assertRegex((d/'private.json').read_text(),r'\n"outbounds":\[')
  self.assertEqual((d/'private.json').stat().st_mode&0o777,0o600)
 def test_profile_rejects_ambiguous_nodes(self):
  for nodes in [[],self.nodes()*2,[dict(self.nodes()[0],detour='other')],[dict(self.nodes()[0],tag='proxy-main')]]:
   result,_=self.profile(nodes);self.assertNotEqual(result.returncode,0)
 def test_profile_rejects_noncanonical_cidr(self):
  result,_=self.profile(self.nodes(),'1.0.1.7/24\n');self.assertNotEqual(result.returncode,0)
 def test_filter_compilation(self):
  source='example.com\n+.example.net\n*.example.org\nstun.*.*\n#comment\n'
  result=run(['awk','-f',str(ROOT/'payload/starts/filter_compile.awk')],input=source)
  self.assertEqual(result.returncode,0);obj=json.loads(result.stdout)
  self.assertEqual(obj['domain'],['example.com']);self.assertEqual(obj['domain_suffix'],['example.net'])
  self.assertTrue(re.match(obj['domain_regex'][0],'one.example.org'));self.assertFalse(re.match(obj['domain_regex'][0],'two.one.example.org'))
  result=run(['awk','-f',str(ROOT/'payload/starts/filter_compile.awk')],input='geosite:category-games\n');self.assertNotEqual(result.returncode,0)
 def test_shipped_filter_valid(self):
  result=run(['awk','-f',str(ROOT/'payload/starts/filter_compile.awk'),str(ROOT/'examples/fake_ip_filter.list')]);self.assertEqual(result.returncode,0);json.loads(result.stdout)
 def test_memory_thresholds_and_bounded_samples(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);proc=d/'proc';(proc/'net').mkdir(parents=True);(proc/'sys/net/netfilter').mkdir(parents=True)
   (proc/'net/sockstat').write_text('TCP: inuse 5 alloc 10 mem 3\nUDP: inuse 2 mem 4\n');(proc/'sys/net/netfilter/nf_conntrack_count').write_text('200')
   (proc/'zoneinfo').write_text('Node 0, zone DMA\n pages free 400\nNode 0, zone Normal\n pages free 2000\n')
   helper=d/'helper.sh';helper.write_text((ROOT/'payload/starts/resource_health.sh').read_text().replace('/proc/',str(proc)+'/'))
   (d/'resources.csv').write_text('\n'.join(','.join(['1','1']+['0']*13) for _ in range(1500))+'\n')
   for available,pressure in [(8000,'protect'),(15000,'warning'),(24000,'normal')]:
    (proc/'meminfo').write_text(f'MemFree: 5000 kB\nMemAvailable: {available} kB\n')
    # Paths are generated internally, no untrusted shell interpolation.
    result=run(['sh','-c',f'. "{helper}"; D="{d}"; now=100; up=100; pid=77; rss=30000; resource_snapshot; printf "%s %s %s %s\\n" "$rh_pressure" "$rh_tcp" "$rh_udp" "$rh_conn"'])
    self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout.strip(),f'{pressure} 12 16 200')
   rows=(d/'resources.csv').read_text().splitlines();self.assertLessEqual(len(rows),1441);self.assertTrue(all(len(x.split(','))==15 for x in rows))
 def test_public_payload_no_private_runtime_files(self):
  forbidden={'config.json','ShellCrash.cfg','command.env','identity.secret','authtoken.secret','sub.raw','cloud-backup-key','api-secret'}
  for p in (ROOT/'payload').rglob('*'):
   self.assertFalse(p.is_symlink());self.assertNotIn(p.name,forbidden)
   if p.is_file():self.assertLess(p.stat().st_size,1024*1024)
 def test_installer_preflight_preserves_custom_hooks(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c=d/'etc/storage/ShellCrash';(c/'configs').mkdir(parents=True);(c/'task').mkdir();(c/'jsons').mkdir()
   (c/'version').write_text('1.9.4release\n');(c/'configs/ShellCrash.cfg').write_text('crashcore=singbox\n')
   (c/'jsons/config.json').write_text('"outbounds":[{"tag":"proxy-main"}]\n')
   (d/'etc/storage/chinadns').mkdir();(d/'etc/storage/chinadns/chnroute.txt').write_text('1.0.1.0/24\n')
   (d/'www').mkdir();(d/'www/state.js').write_text('');(d/'sbin').mkdir();(d/'sbin/mtd_storage.sh').write_text('')
   (d/'tmp').mkdir();(d/'opt').mkdir();shim=d/'bin';shim.mkdir()
   commands={'id':'echo 0','uname':'echo mips','nvram':'case "$2" in lan_ipaddr) echo 192.168.1.1;; ss_enable) echo 0;; esac'}
   for cmd in ['iptables','ipset','mtd_write','sha256sum']:commands[cmd]='exit 0'
   for cmd,body in commands.items():
    f=shim/cmd;f.write_text('#!/bin/sh\n'+body+'\n');f.chmod(0o700)
   script=(ROOT/'install.sh').read_text().replace('export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH','export PATH="'+str(shim)+':$PATH"')
   script=re.sub(r'/(?:etc/storage(?=/|\b)|www/|sbin/|tmp/|opt)',lambda m:str(d)+m.group(0),script)
   f=d/'install-check.sh';f.write_text(script)
   hook=c/'task/bfstart';hook.write_text('echo user-hook\n')
   result=run(['sh',str(f),'--check']);self.assertNotEqual(result.returncode,0);self.assertIn('已有自定义钩子',result.stdout,result.stderr);self.assertEqual(hook.read_text(),'echo user-hook\n')
   hook.unlink();result=run(['sh',str(f),'--check']);self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertIn('预检通过',result.stdout)

class DeployTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  spec=importlib.util.spec_from_file_location('deploy',ROOT/'tools/deploy.py')
  cls.deploy=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.deploy)
 def snapshot(self):
  buffer=io.BytesIO()
  with tarfile.open(fileobj=buffer,mode='w:gz') as t:
   entries={'ShellCrash/jsons/config.json':json.dumps({'outbounds':[{'type':'anytls','tag':'香港01','server':'proxy.example.com','server_port':443,'password':'fixture-only','tls':{'enabled':True}}]}).encode(),'chinadns/chnroute.txt':b'1.0.1.0/24\n'}
   for name,data in entries.items():
    info=tarfile.TarInfo(name);info.size=len(data);t.addfile(info,io.BytesIO(data))
  return buffer.getvalue()
 def test_anytls_plain_and_base64(self):
  raw='anytls://pass%40word@proxy.example.com:443?sni=tls.example.com&alpn=h2,http%2F1.1#香港01'.encode()
  plain=self.deploy.subscription_nodes(raw);self.assertEqual(plain,self.deploy.subscription_nodes(base64.urlsafe_b64encode(raw)))
  self.assertEqual(plain[0]['password'],'pass@word');self.assertEqual(plain[0]['tls']['server_name'],'tls.example.com');self.assertEqual(plain[0]['tls']['alpn'],['h2','http/1.1'])
  self.assertFalse(plain[0]['tls']['insecure'])
 def test_unsupported_link_rejected(self):
  with self.assertRaises(ValueError):self.deploy.subscription_nodes(b'trojan://fixture@proxy.example.com#demo')
 def test_mixed_legacy_ssr_keeps_anytls_nodes(self):
  nodes=self.deploy.subscription_nodes(b'anytls://fixture@proxy.example.com:443#HongKong01\nssr://legacy-fixture')
  self.assertEqual(len(nodes),1);self.assertEqual(nodes[0]['type'],'anytls')
 def test_legacy_only_subscription_cannot_make_empty_configuration(self):
  import base64
  with self.assertRaises(ValueError):self.deploy.subscription_nodes(base64.b64encode(b'ssr://legacy-fixture'))
 def test_snapshot_does_not_extract_paths(self):
  result=self.deploy.read_snapshot(self.snapshot());self.assertIn('chinadns/chnroute.txt',result)
  buffer=io.BytesIO()
  with tarfile.open(fileobj=buffer,mode='w:gz') as t:
   info=tarfile.TarInfo('ShellCrash/jsons/config.json');info.type=tarfile.SYMTYPE;info.linkname='/etc/passwd';t.addfile(info)
  with self.assertRaises(ValueError):self.deploy.read_snapshot(buffer.getvalue())
 def test_upload_contains_only_runtime_files_and_private_inputs(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);(d/'profile').write_text('{}');(d/'secret').write_text('fixture-secret')
   with tarfile.open(fileobj=io.BytesIO(self.deploy.make_upload(d/'profile',d/'secret'))) as t:
    names=t.getnames();self.assertIn('package/install.sh',names);self.assertNotIn('package/.git',names)
    self.assertEqual(t.getmember('panel-secret.private').mode,0o600)
    self.assertEqual(t.extractfile('panel-secret.private').read(),b'fixture-secret')
 def lifecycle(self,install_fails=False,preflight_fails=False,subscription=False,fresh=False,check_only=False):
  original_run=subprocess.run;calls=[];raw=self.snapshot()
  if fresh:
   buffer=io.BytesIO()
   with tarfile.open(fileobj=buffer,mode='w:gz') as t:
    text=b'#!/bin/sh\n';info=tarfile.TarInfo('started_script.sh');info.size=len(text);t.addfile(info,io.BytesIO(text))
   raw=buffer.getvalue()
  with tempfile.TemporaryDirectory() as td:
   def fake_run(argv,**kw):
    if argv[0]!= 'ssh':return original_run(argv,**kw)
    command=argv[-1];calls.append(command)
    if subscription and command.startswith('umask 077;'):
     with tarfile.open(fileobj=io.BytesIO(kw['input'])) as archive:
      self.assertEqual(base64.b64decode(archive.extractfile('subscription.private').read()),b'https://provider.example.com/subscription')
    code=1 if (install_fails and '--install' in command) or (preflight_fails and '--check' in command) else 0
    output=raw if 'ShellCrash/jsons/config.json' in command else None
    if hasattr(kw.get('stdout'),'write'):kw['stdout'].write(raw)
    return subprocess.CompletedProcess(argv,code,stdout=output)
   argv=['deploy.py','--router','192.168.1.1','--user','admin','--port','22','--backup-dir',td]
   if check_only:argv.append('--check-only')
   with patch.object(sys,'argv',argv),patch.object(self.deploy.subprocess,'run',side_effect=fake_run),patch.object(self.deploy.getpass,'getpass',return_value='https://provider.example.com/subscription' if subscription else ''),patch.object(self.deploy.urllib.request,'urlopen',side_effect=lambda *a,**k:io.BytesIO(self.deploy.read_snapshot(self.snapshot())['ShellCrash/jsons/config.json'])),patch('sys.stdout',new=io.StringIO()),patch('sys.stderr',new=io.StringIO()):
    if install_fails or preflight_fails:
     with self.assertRaises(RuntimeError):self.deploy.main()
    else:self.deploy.main()
   backups=list(Path(td).glob('*.tar.gz'))
   if preflight_fails or check_only:
    self.assertFalse(backups);self.assertFalse(any('--install' in c for c in calls))
   else:
    self.assertEqual(len(backups),1);self.assertEqual(backups[0].stat().st_mode&0o777,0o600)
    with tarfile.open(backups[0]) as t:self.assertTrue(t.getnames())
   self.assertTrue(any(c.startswith('rm -rf ') for c in calls))
   return calls
 def test_successful_install_backs_up_before_installing(self):
  calls=self.lifecycle();backup=next(i for i,c in enumerate(calls) if '/package/backup.sh -' in c);install=next(i for i,c in enumerate(calls) if '--install' in c);self.assertLess(backup,install)
 def test_subscription_is_uploaded_and_recorded(self):
  calls=self.lifecycle(subscription=True);self.assertTrue(any('--subscription-file ../subscription.private' in c for c in calls))
 def test_fresh_install_uses_subscription_and_bundled_rules(self):self.lifecycle(fresh=True,subscription=True)
 def test_fresh_preflight_never_installs(self):self.lifecycle(fresh=True,check_only=True)
 def test_failed_install_keeps_local_backup(self):self.lifecycle(install_fails=True)
 def test_failed_preflight_never_installs(self):self.lifecycle(preflight_fails=True)

class BootstrapTests(unittest.TestCase):
 def test_vendor_hashes_and_version(self):
  import hashlib
  vendor=ROOT/'vendor/ShellCrash-1.9.4'
  self.assertEqual((vendor/'version').read_text().strip(),'1.9.4release')
  for line in (vendor/'SHA256SUMS').read_text().splitlines():
   digest,name=line.split('  ',1)
   self.assertEqual(hashlib.sha256((vendor/name).read_bytes()).hexdigest(),digest,name)
 def fixture(self,d,existing=False,fail=False):
  storage=d/'etc/storage';storage.mkdir(parents=True);(storage/'started_script.sh').write_text('#!/bin/sh\necho original-startup\n')
  (d/'www').mkdir();(d/'www/state.js').write_text('');(d/'sbin').mkdir();(d/'sbin/mtd_storage.sh').write_text('')
  (d/'tmp').mkdir();(d/'opt').mkdir();shim=d/'bin';shim.mkdir()
  # Device sed accepts -i without a suffix; emulate this on BSD/macOS.
  sedshim=shim/'sed'
  sedshim.write_text('#!'+sys.executable+'\n'+"import os,re,sys\nif len(sys.argv)>1 and sys.argv[1]=='-i':\n for name in sys.argv[3:]:\n  text=open(name).read().splitlines(True)\n  for rule in sys.argv[2].split(';'):\n   rule=rule.strip()\n   if rule.startswith('/') and rule.endswith('/d'):\n    pattern=rule[1:-2];text=[line for line in text if not re.search(pattern,line)]\n   else: raise SystemExit('Unsupported fixture sed rule')\n  open(name,'w').writelines(text)\nelse: os.execv('/usr/bin/sed',['sed']+sys.argv[1:])\n")
  sedshim.chmod(0o700)
  package=d/'package';package.mkdir()
  shutil.copytree(ROOT/'payload',package/'payload');shutil.copytree(ROOT/'examples',package/'examples');shutil.copytree(ROOT/'vendor',package/'vendor')
  def remap(text):return re.sub(r'/(?:etc/storage(?=/|\b)|www/|sbin/|tmp/|opt)',lambda m:str(d)+m.group(0),text)
  for name in ['install.sh','backup.sh','restore_storage.sh']:
   text=(ROOT/name).read_text()
   text=text.replace('export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH','export PATH="'+str(shim)+':$PATH"')
   (package/name).write_text(remap(text))
  # Simulate only device effects; all installer/backup/restore logic is real.
  (package/'payload/starts/panel_boot.sh').write_text('#!/bin/sh\nexit 0\n')
  (package/'payload/starts/save_storage.sh').write_text('#!/bin/sh\nif [ -f "'+str(d/'fail-once')+'" ]; then rm "'+str(d/'fail-once')+'"; exit 1; fi\ntouch "'+str(d/'saved')+'"\n')
  for p in (package/'payload/starts').glob('*.sh'):p.chmod(0o700)
  commands={'id':'echo 0','uname':'echo mips','nvram':'case "$2" in lan_ipaddr) echo 192.168.1.1;; ss_enable) echo 0;; esac'}
  for cmd in ['iptables','ipset','mtd_write','sha256sum','curl','mount','umount','crontab']:commands[cmd]='exit 0'
  for cmd,body in commands.items():
   p=shim/cmd;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o700)
  env=dict(os.environ,PATH=str(shim)+os.pathsep+os.environ['PATH'])
  c=storage/'ShellCrash'
  if existing:
   (c/'configs').mkdir(parents=True);(c/'jsons').mkdir();(c/'task').mkdir()
   (c/'version').write_text('1.9.4release\n');(c/'configs/ShellCrash.cfg').write_text('crashcore=singbox\noriginal_setting=keep\n')
   (c/'jsons/config.json').write_text('{"original":true}\n')
   (c/'start.sh').write_text('#!/bin/sh\nexit 0\n');(c/'start.sh').chmod(0o700);(c/'menu.sh').write_text('echo old\n')
   (c/'starts').mkdir();(c/'libs').mkdir();(storage/'chinadns').mkdir();(storage/'chinadns/chnroute.txt').write_text('1.0.1.0/24\n')
  profile=d/'config.private.json';secret=d/'secret.private';secret.write_text('a'*48)
  profile.write_text('{\n"outbounds":[{"tag":"proxy-main"}],\n"experimental":{"clash_api":{"external_controller":"192.168.1.1:9999","secret":"'+'a'*48+'"}}\n}\n')
  if fail:(d/'fail-once').touch()
  command=['sh',str(package/'install.sh'),'--install','--profile',str(profile),'--secret-file',str(secret)]
  return storage,c,package,env,command
 def test_fresh_install_and_restore(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);storage,c,package,env,command=self.fixture(d)
   result=run(command,env=env);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   self.assertEqual((c/'version').read_text().strip(),'1.9.4release');self.assertTrue((c/'configs/cn_ip.default.txt').exists());self.assertFalse((storage/'chinadns').exists());self.assertTrue((d/'saved').exists())
   backup=d/'tmp/padavan-panel-before-install.tar.gz'
   with tarfile.open(backup) as t:
    self.assertIn('shellcrash=absent',t.extractfile('_panel_backup_state').read().decode())
   result=run(['sh',str(package/'restore_storage.sh'),str(backup)],env=env);self.assertEqual(result.returncode,0,result.stderr)
   self.assertFalse(c.exists());self.assertFalse((storage/'chinadns').exists());self.assertEqual((storage/'started_script.sh').read_text(),'#!/bin/sh\necho original-startup\n')
 def test_fresh_failure_rolls_back_absent_files(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);storage,c,package,env,command=self.fixture(d,fail=True)
   result=run(command,env=env);self.assertNotEqual(result.returncode,0)
   self.assertFalse(c.exists());self.assertFalse((storage/'chinadns').exists());self.assertTrue((d/'saved').exists())
   self.assertEqual((storage/'started_script.sh').read_text(),'#!/bin/sh\necho original-startup\n')
 def test_existing_install_restores_original_configuration(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);storage,c,package,env,command=self.fixture(d,existing=True,fail=True)
   result=run(command,env=env);self.assertNotEqual(result.returncode,0)
   self.assertEqual((c/'configs/ShellCrash.cfg').read_text(),'crashcore=singbox\noriginal_setting=keep\n');self.assertEqual((c/'jsons/config.json').read_text(),'{"original":true}\n');self.assertFalse((c/'padavan').exists())
   self.assertEqual((storage/'chinadns/chnroute.txt').read_text(),'1.0.1.0/24\n')

if __name__=='__main__':unittest.main(verbosity=2)
