import hashlib,http.server,io,json,os,shlex,struct,subprocess,tarfile,tempfile,threading,unittest
from pathlib import Path
from tools.backup_bundle import Bundle
from tools.restore_k2p import plan_for
ROOT=Path(__file__).resolve().parents[1]
class K2PRestorePlan(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.m=dict(format=2,scope='full-application',model='K2P',core_kind='singbox',core_version='1.12.13',files=[])
  self.elf=bytearray(128);self.elf[:6]=b'\x7fELF\x01\x01';self.elf[18:20]=struct.pack('<H',8)
  self.pack('core.tar.gz',{'CrashCore':self.elf});self.m['core_sha256']=self.m['files'][0]['sha256']
  self.app={'start.sh':b'#!/bin/sh\n','menu.sh':b'#!/bin/sh\n','menus/bot_tg_service.sh':b'# fixture menu','task/afstart':b'# fixture task','backup.info':b'model=K2P\nautostart=1\nenabled=1\ntraffic_mode=rule\n',
    'starts/panel_boot.sh':b'#!/bin/sh\n','configs/ShellCrash.cfg':b'core=singbox\n',
    'configs/core-installed.info':('version=1.12.13\narch=mipsle-softfloat\nsha256='+self.m['core_sha256']+'\n').encode(),
    'jsons/config.json':b'{"outbounds":[{"type":"direct","tag":"DIRECT"}]}'}
  self.pack('application.tar.gz',self.app);self.pack('runtime-assets.tar.gz',{'sc-admin/runtime-backup.info':b'format=2'})
  self.write()
  self.live=dict(installed_program_complete=True,machine='mips',arch='mipsle-softfloat',active=False,remote_ready=True,remote_fingerprint='d'*64,
   protect_mb=12,available_kb=21000,core_sha256=self.m['core_sha256'],core_version='1.12.13',binary_sha256=hashlib.sha256(self.elf).hexdigest(),enabled=1,autostart=1,traffic_mode='rule')
 def tearDown(self):self.tmp.cleanup()
 def pack(self,name,files):
  with tarfile.open(self.root/name,'w:gz')as out:
   for n,data in files.items():
    info=tarfile.TarInfo(n);info.size=len(data);info.mode=0o700;out.addfile(info,io.BytesIO(data))
  p=self.root/name;self.m['files']=[r for r in self.m['files']if r['name']!=name]+[dict(name=name,size=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())]
 def write(self):(self.root/'manifest.json').write_text(json.dumps(self.m))
 def plan(self,**args):
  with Bundle(self.root,'K2P')as bundle:return plan_for(bundle,args.get('prefix',''),args.get('live',self.live),'0123abcd',args.get('failure','none'))
 def test_same_core_plan_has_streamed_binary_and_explicit_startup_state(self):
  p=self.plan();self.assertEqual(p['binary_sha256'],self.live['binary_sha256']);self.assertEqual(p['target_mode'],'rule')
  self.assertEqual(p['core_member'],'CrashCore');self.assertEqual(p['previous_enabled'],1)
 def test_architecture_busy_disabled_low_memory_and_changed_binary_fail_closed(self):
  for delta in [dict(installed_program_complete=False),dict(machine='armv7l'),dict(arch='mips'),dict(active=True),dict(remote_ready=False),dict(available_kb=13000),dict(binary_sha256='e'*64),dict(core_sha256='f'*64),dict(enabled=2),dict(traffic_mode='bad')]:
   with self.subTest(delta=delta),self.assertRaises(ValueError):self.plan(live={**self.live,**delta})
 def test_old_backup_missing_start_state_or_wrong_core_record_rejected(self):
  for name,value in [('backup.info',b'model=K2P\n'),('configs/core-installed.info',b'arch=mipsle-softfloat\nsha256=wrong\n')]:
   old=self.app[name];self.app[name]=value;self.pack('application.tar.gz',self.app);self.write()
   with self.assertRaises(ValueError):self.plan()
   self.app[name]=old
 def test_invalid_path_and_failure_are_rejected(self):
  for prefix in ['../a','http://other','imports/a/../b','/absolute']:
   with self.assertRaises(ValueError):self.plan(prefix=prefix)
  with self.assertRaises(ValueError):self.plan(failure='kill')

class K2PStreamCore(unittest.TestCase):
 def test_real_stream_is_bounded_and_never_extracts_sibling_paths(self):
  with tempfile.TemporaryDirectory()as tmp:
   p=Path(tmp);binary=b'fixture binary'*10000
   out=io.BytesIO()
   with tarfile.open(fileobj=out,mode='w:gz')as tar:
    for name,contents in [('../should-not-exist',b'bad'),('CrashCore',binary)]:
     info=tarfile.TarInfo(name);info.size=len(contents);tar.addfile(info,io.BytesIO(contents))
   data=out.getvalue()
   class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
     body=data if self.path=='/valid'else data[:40]
     self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
   server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
   try:
    source=(ROOT/'profiles/k2p/payload/starts/restore-worker.sh').read_text()
    function=source[source.index('stream_core(){'):source.index('\nclear_app(){')]
    for route,sha,expected in [('valid',hashlib.sha256(binary).hexdigest(),True),('valid','a'*64,False),('short',hashlib.sha256(binary).hexdigest(),False)]:
     (p/'plan').write_text('core_size='+str(len(data))+'\ncore_member=CrashCore\nbinary_size='+str(len(binary))+'\nbinary_sha256='+sha+'\n')
     script='set -e\nX='+shlex.quote(tmp)+'\nfield(){ sed -n "s/^$1=//p" "$X/plan"; };dav_curl(){ curl -sS "$@"; };\n'
     script+='hash(){ shasum -a 256 "$1" | awk \'{print $1}\'; };checked(){ [ "$(wc -c < "$1" | tr -d \' \')" = "$2" ] && [ "$(hash "$1")" = "$3" ]; };\n'+function
     script+='\nstream_core '+shlex.quote('http://127.0.0.1:'+str(server.server_port)+'/'+route)+' "$X/core"\n'
     run=subprocess.run(['sh','-c',script],capture_output=True,timeout=15,cwd=tmp)
     self.assertEqual(run.returncode==0,expected,run.stderr[-300:]);self.assertFalse((p.parent/'should-not-exist').exists())
     self.assertFalse(list(p.glob('*.tar.gz')))
   finally:server.shutdown();server.server_close();thread.join()
class K2PRollback(unittest.TestCase):
 def test_prewrite_failure_restores_runtime_before_restart(self):
  self.check(False)
 def test_persistence_failure_must_not_report_recovered(self):
  self.check(True)
 def check(self,fail_save):
  source=(ROOT/'profiles/k2p/payload/starts/restore-worker.sh').read_text()
  function=source[source.index('rollback(){'):source.index('\nfinish(){')]
  with tempfile.TemporaryDirectory()as tmp:
   p=Path(tmp);(p/'configs').mkdir();(p/'save_storage.sh').write_text('#!/bin/sh\necho PERSIST\nexit '+('1'if fail_save else '0')+'\n')
   script='set -e\nX='+shlex.quote(tmp)+';C=$X;R=$X;CHECKPOINT=fixture;MUTATED=0\n'
   script+="field(){ case $1 in previous_enabled)echo 1;;previous_mode)echo rule;;esac; };phase(){ :; };stop(){ :; };clear_runtime(){ :; };restore_runtime(){ echo RUNTIME; };stream_core(){ echo BINARY; };start_check(){ echo STARTED; };\n"
   script+=function+'\nif rollback;then echo RECOVERED;else echo FAILED;fi\n'
   run=subprocess.run(['sh','-c',script],capture_output=True,text=True,timeout=3)
   self.assertEqual(run.returncode,0,run.stderr)
   self.assertIn('RUNTIME\nBINARY',run.stdout)
   if fail_save:self.assertIn('FAILED',run.stdout);self.assertNotIn('STARTED',run.stdout)
   else:self.assertIn('STARTED\nRECOVERED',run.stdout)

class K2PStopFailure(unittest.TestCase):
 def test_live_core_stop_failure_restores_watchdog_and_enabled_flag(self):
  source=(ROOT/'profiles/k2p/payload/starts/restore-worker.sh').read_text()
  function=source[source.index('stop(){'):source.index('\nclear_runtime(){')]
  with tempfile.TemporaryDirectory()as tmp:
   p=Path(tmp);(p/'configs').mkdir();cron=p/'cron';cron.write_text('watchdog fixture\n')
   (p/'start.sh').write_text('#!/bin/sh\n: > '+shlex.quote(str(cron))+'\nexit 1\n');(p/'start.sh').chmod(0o700)
   script='set -e\nX='+shlex.quote(tmp)+';C=$X\n'
   script+='crontab(){ if [ "$1" = -l ];then cat "$X/cron";else cp "$1" "$X/cron";fi; };pidof(){ echo 123; };sleep(){ :; };\n'+function
   script+='\nif stop;then exit 9;fi\n'
   run=subprocess.run(['sh','-c',script],capture_output=True,timeout=10)
   self.assertEqual(run.returncode,0,run.stderr);self.assertEqual(cron.read_text(),'watchdog fixture\n');self.assertFalse((p/'configs/panel-disabled').exists())

if __name__=='__main__':unittest.main()
