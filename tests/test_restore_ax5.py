import hashlib
import http.server
import os
import shlex
import subprocess
import threading
import io
import json
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
from tools.backup_bundle import Bundle
from tools.restore_ax5 import plan_for

class AX5RestorePlan(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.m=dict(format=2,scope='full-application',model='AX5',core_version='1.0',core_kind='meta',files=[])
        elf=bytearray(128);elf[:6]=b'\x7fELF\x01\x01';elf[18:20]=struct.pack('<H',40)
        self.pack('core.tar.gz',{'CrashCore':bytes(elf)})
        core=self.m['files'][0]['sha256'];self.m['core_sha256']=core
        self.app={'backup.info':b'format=1\nmodel=AX5\n','configs/config.json':b'{}','configs/enabled':b'1\n',
                  'ax5/api.lua':b'-- test','ShellCrash-tool/configs/ShellCrash.cfg':b'core=meta',
                  'cache/core.sha256':core.encode(),'cache/core.env':('HASH="'+core+'"\n').encode()}
        self.pack('application.tar.gz',self.app)
        self.pack('runtime-assets.tar.gz',{'ShellCrash/runtime-backup.info':b'fixture'})
        self.write()
        self.live=dict(core_sha256=core,configured_core_sha256=core,remote_ready=True,remote_fingerprint='d'*64,
                       core_kind='meta',core_version='1.0',
                       machine='armv7l',active=False,protect_mb=14,available_kb=20000,core_size=1000,
                       flash_free_kb=512,application_kb=4000)
    def tearDown(self):self.tmp.cleanup()
    def pack(self,name,files):
        path=self.root/name
        with tarfile.open(path,'w:gz')as out:
            for n,data in files.items():
                info=tarfile.TarInfo(n);info.size=len(data);info.mode=0o700;out.addfile(info,io.BytesIO(data))
        self.m['files']=[r for r in self.m['files']if r['name']!=name]+[dict(name=name,size=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())]
    def write(self):(self.root/'manifest.json').write_text(json.dumps(self.m))
    def plan(self,**kw):
        with Bundle(self.root,'AX5')as b:return plan_for(b,kw.get('prefix',''),kw.get('live',self.live),'0123abcd',kw.get('failure','none'))
    def test_valid_plan_binds_identity_and_budget_without_mutation(self):
        p=self.plan(prefix='baselines/working-test')
        self.assertEqual(p['core_sha256'],self.m['core_sha256']);self.assertEqual(p['remote_fingerprint'],'d'*64)
        self.assertEqual(p['application_path'],'baselines/working-test/application.tar.gz')
        self.assertGreater(p['peak_bytes'],2*1024*1024)
    def test_disabled_wrong_host_mismatched_installed_record_busy_or_low_resources_reject(self):
        for changes in [dict(remote_ready=False),dict(machine='mips'),dict(active=True),dict(available_kb=12000),
                        dict(configured_core_sha256='f'*64),dict(application_kb=0,flash_free_kb=1)]:
            with self.subTest(changes=changes),self.assertRaises(ValueError):self.plan(live={**self.live,**changes})
    def test_external_and_traversal_prefix_or_unknown_fault_reject(self):
        for prefix in ['../other','https://other','baselines/a/../../b','imports/name;sh','/absolute']:
            with self.assertRaises(ValueError):self.plan(prefix=prefix)
        with self.assertRaises(ValueError):self.plan(failure='kill-device')
    def test_legacy_hash_only_in_env_is_verified_but_wrong_internal_hash_rejects(self):
        del self.app['cache/core.sha256'];self.pack('application.tar.gz',self.app);self.write();self.plan()
        self.app['cache/core.env']=b'HASH="'+b'a'*64+b'"\n';self.pack('application.tar.gz',self.app);self.write()
        with self.assertRaises(ValueError):self.plan()
    def test_bad_internal_model_start_state_or_configuration_rejects(self):
        for name,value in [('backup.info',b'model=K2P\n'),('configs/enabled',b'anything'),('configs/config.json',b'{broken')]:
            old=self.app[name];self.app[name]=value;self.pack('application.tar.gz',self.app);self.write()
            with self.assertRaises(ValueError):self.plan()
            self.app[name]=old



class AX5RestoreHealth(unittest.TestCase):
    def test_real_http_requires_saved_api_header_and_matching_version(self):
        seen=[]
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                auth=self.headers.get('Authorization');seen.append(auth)
                self.send_response(200 if auth=='Bearer fixture-token' else 401);self.end_headers()
                self.wfile.write(b'{"version":"v1.0"}')
            def log_message(self,*args):pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            source=(Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/restore-worker.sh').read_text()
            function=source[source.index('start_and_check(){'):source.index('\nrollback(){')]
            function=function.replace('/etc/init.d/shellcrash start || return 1','true')
            function=function.replace('http://127.0.0.1:9999/version','http://127.0.0.1:'+str(server.server_port)+'/version')
            with tempfile.TemporaryDirectory()as tmp:
                root=Path(tmp);(root/'configs').mkdir();(root/'service-ready').write_text('1')
                lua=root/'lua';lua.write_text('#!/usr/bin/env python3\nimport os,json,re\nv=json.load(open(os.environ["SC_RESTORE_HEALTH_FILE"]))\nassert isinstance(v.get("version"),str) and re.sub("^v","",v["version"])==re.sub("^v","",os.environ["SC_RESTORE_HEALTH_VERSION"])\n');lua.chmod(0o700)
                for token,version,success in [('fixture-token','1.0',True),('wrong-token','1.0',False),('fixture-token','2.0',False)]:
                    (root/'configs/api-header').write_text('Authorization: Bearer '+token)
                    script='set -e\nC='+shlex.quote(tmp)+';R=$C;X=$C\npidof(){ echo 1234; };sleep(){ :; };\n'+function+'\nstart_and_check 1 '+version
                    run=subprocess.run(['sh','-c',script],env={**os.environ,'PATH':tmp+os.pathsep+os.environ['PATH']},capture_output=True,timeout=12)
                    self.assertEqual(run.returncode==0,success,run.stderr[-400:])
                self.assertIn('Bearer fixture-token',seen);self.assertIn('Bearer wrong-token',seen)
        finally:server.shutdown();server.server_close();thread.join()

class AX5RestoreRollback(unittest.TestCase):
    def test_failed_rollback_write_never_reports_healthy(self):
        # rollback is invoked by an if: POSIX shells suppress errexit there.
        # Exercise real function control flow with failed storage operations.
        source=(Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/restore-worker.sh').read_text()
        function=source[source.index('rollback(){'):source.index('\nfinish(){')]
        for failure in ('clear_app','credentials','cp'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as tmp:
                definitions='\n'.join(name+'(){ '+('return 1' if name==failure else ':')+'; }' for name in ('clear_app','credentials','cp'))
                script='set -e\nX='+shlex.quote(tmp)+';C=$X;T=$X;OLD_CORE=fixture;ORIGINAL_ENABLED=1;MUTATED=1\n'
                script+='phase(){ :; };stop(){ :; };clear_runtime(){ :; };tar(){ :; };rm(){ :; };hash(){ echo fixture; };start_and_check(){ echo HEALTH_CHECK; };\n'
                script+=definitions+'\n'+function+'\nif rollback;then echo ACCEPTED;else echo REJECTED;fi\n'
                run=subprocess.run(['sh','-c',script],capture_output=True,text=True,timeout=3)
                self.assertEqual(run.returncode,0,run.stderr)
                self.assertEqual(run.stdout.strip(),'REJECTED')

if __name__=='__main__':unittest.main()
