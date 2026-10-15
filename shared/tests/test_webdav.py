"""Exercise the shipped shell transport against a local authenticated DAV server."""
import base64
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ax5' if (ROOT / 'ax5').is_dir() else ROOT / 'payload' / 'starts'
AUTH = 'Basic ' + base64.b64encode(b'test:secret').decode()

class DAV(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def handle_request(self):
        self.server.calls.append((self.command, self.path))
        if self.headers.get('Authorization') != getattr(self.server, 'auth', AUTH):
            self.send_response(401); self.end_headers(); return
        objects = self.server.objects
        status, body = 204, b''
        if self.command == 'PROPFIND':
            status = getattr(self.server, 'preflight_status', 207)
        elif self.command == 'OPTIONS':
            status = 200
        elif self.command == 'MKCOL':
            status = 201
        elif self.command == 'PUT':
            body_in = self.rfile.read(int(self.headers['Content-Length']))
            if getattr(self.server, 'fail_put', '') in self.path and getattr(self.server, 'fail_put', ''):
                status = 507
            else:
                objects[self.path] = body_in
                status = 201
        elif self.command == 'GET':
            status = 200 if self.path in objects else 404
            body = objects.get(self.path, b'')
            if getattr(self.server, 'corrupt_get', '') in self.path and getattr(self.server, 'corrupt_get', ''):
                body += b'corrupt'
        elif self.command == 'DELETE':
            objects.pop(self.path, None)
        elif self.command == 'COPY':
            from urllib.parse import urlsplit
            target=urlsplit(self.headers['Destination']).path
            status=getattr(self.server, 'copy_status', 201)
            if self.path not in objects: status=404
            if target in objects and self.headers.get('Overwrite')=='F': status=412
            if status in (201,204): objects[target]=objects[self.path]
        elif self.command == 'MOVE':
            from urllib.parse import urlsplit
            objects[urlsplit(self.headers['Destination']).path] = objects.pop(self.path)
            if getattr(self.server, 'corrupt_after_move', False) and self.path.endswith('application-latest.json.new'):
                self.server.corrupt_get='application-latest.json'
            if getattr(self.server, 'corrupt_baseline_after_move', False) and self.path.endswith('baseline-latest.json.new'):
                self.server.corrupt_get='baseline-latest.json'
        self.send_response(status); self.send_header('Content-Length', str(len(body))); self.end_headers()
        self.wfile.write(body)
    do_PROPFIND = do_GET = do_PUT = do_MKCOL = do_DELETE = do_MOVE = do_COPY = do_OPTIONS = handle_request

class WebDAV(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root/'configs').mkdir(); (self.root/'starts').mkdir(); (self.root/'ax5').mkdir()
        (self.root/'version').write_text('1.9.4release')
        (self.root/'starts/panel-version').write_text('1.0.0-test')
        (self.root/'configs/core-installed.info').write_text('version=1.12.13\nsha256='+('0'*64)+'\n')
        for name in ('remote.sh', 'webdav.sh', 'remote-settings.sh'):
            shutil.copyfile(SOURCE/name, self.root/'starts'/name)
            shutil.copyfile(SOURCE/name, self.root/'ax5'/name)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), DAV)
        self.server.calls = []; self.server.objects = {}
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.base = 'http://127.0.0.1:%s/dav' % self.server.server_port
        saved = self.save(); self.assertEqual(saved.returncode, 0, saved.stderr)
    def test_detailed_failure_feedback_and_expired_save(self):
        helper='. "$C/starts/remote-settings.sh"; '
        for line, expected in [('HTTP=401','账号或密码'),('HTTP=403','读写权限'),('HTTP=404','路径不存在'),('HTTP=405','写入操作'),('curl: (28) timeout','超时'),('curl: (7) failed','无法连接')]:
            (self.root/'error.log').write_text(line)
            result=self.run_shell(helper+'remote_settings_error "$D/error.log"')
            self.assertIn(expected,result.stdout.decode())
        self.save(enabled='0');before=(self.root/'configs/mirror.conf').read_bytes();self.draft()
        result=self.run_shell(helper+'remote_settings_commit "$D/input"')
        self.assertEqual(result.returncode,3);self.assertIn('重新测试',result.stdout.decode())
        self.assertEqual((self.root/'configs/mirror.conf').read_bytes(),before)

    def test_disabled_account_change_does_not_reuse_previous_credentials(self):
        result = self.save(user=b'other', password=b'', enabled='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root/'configs/webdav.auth').exists())
        result = self.save(user=b'other', password=b'', enabled='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.server.calls, [])

    def test_connection_status_is_gated_cached_and_reports_auth_error(self):
        import json
        self.server.calls.clear()
        self.assertEqual(json.loads(self.run_shell('dav_status').stdout)['state'], 'unverified')
        self.assertEqual(self.server.calls, [])
        self.verify(); self.server.calls.clear()
        self.assertEqual(json.loads(self.run_shell('dav_status').stdout)['state'], 'connected')
        calls = list(self.server.calls)
        self.assertEqual(json.loads(self.run_shell('dav_status').stdout)['state'], 'connected')
        self.assertEqual(self.server.calls, calls)
        (self.root/'remote-status.json').unlink()
        self.server.auth = 'Basic rejected'
        self.assertEqual(json.loads(self.run_shell('dav_status').stdout)['state'], 'unauthorized')
        self.save(enabled='0'); self.server.calls.clear()
        self.assertEqual(json.loads(self.run_shell('dav_status').stdout)['state'], 'disabled')
        self.assertEqual(self.server.calls, [])

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()
    def run_shell(self, script):
        env = dict(os.environ, C=str(self.root), D=str(self.root))
        return subprocess.run(['sh', '-c', '. "$C/starts/remote.sh"; '+script], env=env, capture_output=True)
    def save(self, base=None, password=b'secret', enabled='1', user=b'test'):
        lines = [f'enabled={enabled}', 'transport=webdav']
        for key, value in [('base', (base or self.base).encode()), ('user', user), ('password', password)]:
            lines.append(key+'_b64='+base64.b64encode(value).decode())
        (self.root/'input').write_text('\n'.join(lines)+'\n')
        return self.run_shell('. "$C/starts/remote-settings.sh"; remote_settings_save "$D/input"')
    def verify(self):
        result = self.run_shell('remote_verify')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any('probe-' in path for path in self.server.objects))
    def draft(self, password=b'secret', enabled='1'):
        lines=[f'enabled={enabled}','transport=webdav']
        for k,v in [('base',self.base.encode()),('user',b'test'),('password',password)]:lines.append(k+'_b64='+base64.b64encode(v).decode())
        (self.root/'input').write_text('\n'.join(lines)+'\n')
    def test_candidate_test_before_enable_is_isolated(self):
        self.save(enabled='0'); original=(self.root/'configs/mirror.conf').read_bytes();self.draft()
        cmd='. "$C/starts/remote-settings.sh"; SC_REMOTE_REQUIRE_TEST=1 remote_settings_save "$D/input"'
        self.assertEqual(self.run_shell(cmd).returncode,3)
        self.assertEqual((self.root/'configs/mirror.conf').read_bytes(),original)
        r=self.run_shell('. "$C/starts/remote-settings.sh"; remote_settings_test "$D/input"')
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((self.root/'configs/mirror.conf').read_bytes(),original)
        self.assertNotEqual(self.run_shell('remote_ready').returncode,0)
        calls=list(self.server.calls);self.assertEqual(self.run_shell(cmd).returncode,0);self.assertEqual(self.run_shell('remote_ready').returncode,0)
        self.assertEqual(self.server.calls,calls,'save must use tested proof instead of connecting again')
    def test_failed_candidate_and_changed_parameters_cannot_save(self):
        self.save(enabled='0'); original=(self.root/'configs/mirror.conf').read_bytes();self.draft(password=b'wrong')
        r=self.run_shell('. "$C/starts/remote-settings.sh"; remote_settings_test "$D/input"');self.assertNotEqual(r.returncode,0)
        self.assertEqual((self.root/'configs/mirror.conf').read_bytes(),original);self.assertFalse((self.root/'remote-draft.verified').exists())
        self.draft();self.assertEqual(self.run_shell('. "$C/starts/remote-settings.sh"; remote_settings_test "$D/input"').returncode,0)
        self.draft(password=b'changed');self.assertEqual(self.run_shell('. "$C/starts/remote-settings.sh"; SC_REMOTE_REQUIRE_TEST=1 remote_settings_save "$D/input"').returncode,3)
    def test_expired_candidate_requires_retest(self):
        self.save(enabled='0');self.draft();self.assertEqual(self.run_shell('. "$C/starts/remote-settings.sh"; remote_settings_test "$D/input"').returncode,0)
        (self.root/'remote-draft.checked').write_text('0\n')
        self.assertEqual(self.run_shell('. "$C/starts/remote-settings.sh"; SC_REMOTE_REQUIRE_TEST=1 remote_settings_save "$D/input"').returncode,3)
    def test_verified_roundtrip_and_manifest(self):
        self.verify(); data = b'archive fixture'; digest = hashlib.sha256(data).hexdigest()
        (self.root/'archive').write_bytes(data)
        result = self.run_shell('remote_put backup "$D/archive" tar.gz; remote_fetch backup '+digest+' tar.gz "$D/restored" 1024')
        self.assertEqual(result.returncode, 0, result.stderr); self.assertEqual((self.root/'restored').read_bytes(), data)
        (self.root/'info').write_text('KIND=meta\nVERSION=1.19.28\nHASH='+digest+'\n')
        result = self.run_shell('remote_put info "$D/info" txt >/dev/null; remote_manifest meta')
        self.assertEqual(result.returncode, 0, result.stderr); self.assertEqual(result.stdout, (self.root/'info').read_bytes())
    def test_only_latest_backup_after_verified_publication(self):
        self.verify(); digests = []
        for data in (b'first backup', b'second backup'):
            (self.root/'archive').write_bytes(data); digests.append(hashlib.sha256(data).hexdigest())
            result = self.run_shell('remote_put backup "$D/archive" tar.gz')
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(digests[0] in path for path in self.server.objects))
        self.assertTrue(any(digests[1] in path for path in self.server.objects))
        import json
        index = json.loads(self.server.objects['/dav/shellcrash-panel/K2P/backups/application-latest.json'])
        self.assertEqual(index['sha256'], digests[1]); self.assertEqual(index['tool_version'], '1.9.4release'); self.assertEqual(index['panel_version'], '1.0.0-test')
    def test_off_and_unverified_never_connect(self):
        for enabled in ('1', '0'):
            self.save(enabled=enabled); self.server.calls.clear()
            result = self.run_shell('remote_fetch core '+('0'*64)+' tar.gz "$D/restored" 100')
            self.assertEqual(result.returncode, 2); self.assertEqual(self.server.calls, []); self.assertFalse((self.root/'restored').exists())
    def test_changed_credentials_invalidate_gate(self):
        self.verify(); self.save(password=b'changed'); self.server.calls.clear()
        self.assertNotEqual(self.run_shell('remote_ready').returncode, 0); self.assertEqual(self.server.calls, [])
    def test_bad_password_and_failed_verification_remove_marker(self):
        self.verify(); (self.root/'configs/webdav.auth').write_text('user = "test:wrong"\n')
        result = self.run_shell('remote_verify')
        self.assertNotEqual(result.returncode, 0); self.assertFalse((self.root/'configs/remote.verified').exists())
        self.assertNotIn(b'secret', result.stdout+result.stderr)
    def test_corruption_and_size_limit_remove_partial_file(self):
        self.verify(); digest = hashlib.sha256(b'expected').hexdigest()
        path = '/dav/shellcrash-panel/K2P/objects/core-'+digest+'.tar.gz'
        for content, limit in [(b'corrupt', 100), (b'x'*200, 20)]:
            self.server.objects[path] = content
            result = self.run_shell('remote_fetch core '+digest+' tar.gz "$D/restored" '+str(limit))
            self.assertNotEqual(result.returncode, 0); self.assertFalse((self.root/'restored').exists())
    def test_invalid_input_preserves_settings_and_blank_keeps_password(self):
        original = (self.root/'configs/webdav.auth').read_bytes()
        self.assertEqual(self.save(password=b'').returncode, 0)
        self.assertEqual((self.root/'configs/webdav.auth').read_bytes(), original)
        for password in (b'newline\nsecret', b'nul\x00secret', b'del\x7fsecret'):
            self.assertNotEqual(self.save(password=password).returncode, 0)
            self.assertEqual((self.root/'configs/webdav.auth').read_bytes(), original)
        self.assertNotEqual(self.save(base=self.base+'/../outside').returncode, 0)
        self.assertNotEqual(self.save(password=b'', user=b'other').returncode, 0)
        self.assertEqual((self.root/'configs/webdav.auth').stat().st_mode & 0o777, 0o600)


    def test_catalog_survives_ram_reset_and_distinguishes_failure_from_absence(self):
        import json
        self.verify()
        record={"format":1,"created":123,"sha256":"a"*64,"size":1234}
        pointer='/dav/shellcrash-panel/K2P/backups/application-latest.json'
        # Discover the fixture base path instead of assuming the caller's URL path.
        from urllib.parse import urlparse
        pointer=urlparse(self.base).path.rstrip('/')+'/shellcrash-panel/K2P/backups/application-latest.json'
        self.server.objects[pointer]=json.dumps(record,separators=(',',':')).encode()
        for name in ['remote-application.json','remote-config.json','remote-catalog.key']:
            (self.root/name).unlink(missing_ok=True)
        data=json.loads(self.run_shell('dav_catalog').stdout)
        self.assertEqual(data['state'],'ready')
        self.assertEqual(json.loads(base64.b64decode(data['application_b64'])),record)
        self.server.auth='Basic rejected'
        data=json.loads(self.run_shell('dav_catalog').stdout)
        self.assertEqual(data['state'],'error');self.assertTrue(data['application_b64'])
        self.server.auth=AUTH;del self.server.objects[pointer]
        data=json.loads(self.run_shell('dav_catalog').stdout)
        self.assertEqual(data['state'],'empty');self.assertEqual(data['application_b64'],'')
        self.save(enabled='0');self.server.calls.clear()
        self.assertEqual(json.loads(self.run_shell('dav_catalog').stdout)['state'],'disabled')
        self.assertEqual(self.server.calls,[])

    def test_live_gate_rejects_redirects_unavailable_and_changed_auth_before_payload(self):
        self.verify()
        (self.root/'archive').write_bytes(b'payload')
        for status in [302, 401, 503]:
            self.server.preflight_status=status;self.server.calls.clear()
            result=self.run_shell('remote_put core "$D/archive" tar.gz')
            self.assertNotEqual(result.returncode,0)
            self.assertEqual([m for m,p in self.server.calls],['PROPFIND'])
        self.server.preflight_status=207;self.server.calls.clear()
        (self.root/'configs/webdav.auth').write_text('user = "changed:invalid"\n')
        self.assertNotEqual(self.run_shell('remote_put core "$D/archive" tar.gz').returncode,0)
        self.assertEqual(self.server.calls,[])

    def test_live_gate_is_transaction_local_not_persisted_online_permission(self):
        self.verify();self.server.calls.clear()
        (self.root/'archive').write_bytes(b'payload')
        result=self.run_shell('remote_put core "$D/archive" tar.gz;remote_put core "$D/archive" tar.gz')
        self.assertEqual(result.returncode,0,result.stderr)
        # Function calls share one process, but subshell-based transports cannot
        # carry permission into later jobs. At least one live check precedes each.
        methods=[m for m,p in self.server.calls]
        self.assertGreaterEqual(methods.count('PROPFIND'),1)
        self.assertEqual(methods.count('PUT'),2)
        self.server.preflight_status=503;self.server.calls.clear()
        self.assertNotEqual(self.run_shell('remote_put core "$D/archive" tar.gz').returncode,0)
        self.assertEqual([m for m,p in self.server.calls],['PROPFIND'])

    def full_set(self, model='K2P'):
        self.verify()
        app=self.root/'application.tar.gz';app.write_bytes(b'new installed application')
        assets=self.root/'runtime.tar.gz';assets.write_bytes(b'current runtime resources')
        core=b'expected current kernel';digest=hashlib.sha256(core).hexdigest()
        (self.root/'configs/core-installed.info').write_text('version=1.12.13\nsha256='+digest+'\narchive_size='+str(len(core))+'\n')
        (self.root/'cache').mkdir(exist_ok=True);(self.root/'cache/core-armv7.tar.gz').write_bytes(core)
        tool=self.root/'tool';tool.mkdir(exist_ok=True);(tool/'version').write_text('1.9.4release')
        self.server.objects['/dav/shellcrash-panel/'+model+'/objects/core-'+digest+'.tar.gz']=core
        script=SOURCE/'backup-set.sh'
        script_text=script.read_text().replace('/data/ShellCrash-tool/version',str(tool/'version'))
        (self.root/'backup-set.sh').write_text(script_text)
        return ('REMOTE_MODEL='+model+';export REMOTE_MODEL;hash='+digest+';version=1.12.13;KIND=meta;panel_version=1.0.0-test;protect_kb=12288;'
                '. "$C/backup-set.sh";backup_resources_pack(){ resources="$D/runtime.tar.gz"; };backup_set_publish "$D/application.tar.gz"')

    def test_complete_manifest_and_baseline_survive_latest_replacement(self):
        import json
        for model in ['K2P','AX5']:
            command=self.full_set(model)
            prefix='/dav/shellcrash-panel/'+model
            old_app='a'*64;old_runtime='b'*64
            old={'format':2,'files':[{'path':'backups/backup-'+old_app+'.tar.gz'}, {'path':'objects/runtime-'+old_runtime+'.tar.gz'}]}
            pointer=prefix+'/backups/application-latest.json'
            self.server.objects[pointer]=json.dumps(old,separators=(',',':')).encode()
            old_paths=[prefix+'/backups/backup-'+old_app+'.tar.gz',prefix+'/objects/runtime-'+old_runtime+'.tar.gz']
            for p in old_paths:self.server.objects[p]=b'old'
            baseline=prefix+'/baselines/working/foundation.tar.gz';self.server.objects[baseline]=b'baseline'
            result=self.run_shell(command);self.assertEqual(result.returncode,0,result.stderr)
            record=json.loads(self.server.objects[pointer]);self.assertEqual(record['format'],2);self.assertEqual(record['model'],model)
            self.assertEqual(len(record['files']),3)
            for f in record['files']:
                data=self.server.objects[prefix+'/'+f['path']]
                self.assertEqual(len(data),f['size']);self.assertEqual(hashlib.sha256(data).hexdigest(),f['sha256'])
            self.assertEqual(record['size'],sum(f['size'] for f in record['files']))
            self.assertEqual(self.server.objects[baseline],b'baseline')
            self.assertNotIn(prefix+'/backups/application-previous.json',self.server.objects)
            for p in old_paths:self.assertNotIn(p,self.server.objects)

    def test_failed_or_corrupt_component_preserves_previous_complete_backup(self):
        for fault in ['fail_put','corrupt_get']:
            command=self.full_set();pointer='/dav/shellcrash-panel/K2P/backups/application-latest.json'
            old=b'{"format":1,"sha256":"'+b'a'*64+b'"}'
            self.server.objects[pointer]=old;old_path='/dav/shellcrash-panel/K2P/backups/backup-'+('a'*64)+'.tar.gz';self.server.objects[old_path]=b'previous'
            setattr(self.server,fault,'runtime-')
            result=self.run_shell(command);self.assertNotEqual(result.returncode,0)
            self.assertEqual(self.server.objects[pointer],old);self.assertEqual(self.server.objects[old_path],b'previous')
            setattr(self.server,fault,'')

    def test_corrupt_staged_index_never_replaces_latest(self):
        command=self.full_set();prefix='/dav/shellcrash-panel/K2P/backups/'
        old=b'{"format":1,"sha256":"'+b'a'*64+b'"}'
        self.server.objects[prefix+'application-latest.json']=old
        self.server.corrupt_get='application-latest.json.new'
        result=self.run_shell(command)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.server.objects[prefix+'application-latest.json'],old)
        self.assertEqual(self.server.objects[prefix+'application-previous.json'],old)
        self.assertNotIn(prefix+'application-latest.json.new',self.server.objects)
        self.assertFalse(any(m=='MOVE' and p.endswith('application-latest.json.new') for m,p in self.server.calls))

    def test_uncertain_published_index_preserves_previous_and_objects(self):
        command=self.full_set();prefix='/dav/shellcrash-panel/K2P/'
        old=b'{"format":1,"sha256":"'+b'a'*64+b'"}'
        old_object=prefix+'backups/backup-'+('a'*64)+'.tar.gz'
        self.server.objects[prefix+'backups/application-latest.json']=old
        self.server.objects[old_object]=b'previous'
        # Fail only the final readback, after the MOVE, not reading old latest.
        self.server.corrupt_after_move=True
        result=self.run_shell(command)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.server.objects[prefix+'backups/application-previous.json'],old)
        self.assertEqual(self.server.objects[old_object],b'previous')

    def prepare_baseline(self):
        command=self.full_set()
        result=self.run_shell(command);self.assertEqual(result.returncode,0,result.stderr)
        for name in ['backup-baseline.sh','backup-guide.sh','backup-manifest.awk']:
            shutil.copyfile(SOURCE/name,self.root/'starts'/name)
            shutil.copyfile(SOURCE/name,self.root/'ax5'/name)
        return '. "$C/starts/backup-baseline.sh";baseline_create'

    def test_baseline_is_a_verified_independent_copy_with_guide(self):
        import json
        command=self.prepare_baseline();prefix='/dav/shellcrash-panel/K2P/'
        result=self.run_shell(command);self.assertEqual(result.returncode,0,result.stderr)
        pointer=json.loads(self.server.objects[prefix+'baselines/baseline-latest.json'])
        directory=pointer['path'].removesuffix('manifest.json')
        manifest=json.loads(self.server.objects[prefix+pointer['path']])
        self.assertEqual(manifest['default_restore'],'full-confirmed')
        self.assertEqual(manifest['scope'],'full-application-baseline')
        for item in manifest['files']:
            data=self.server.objects[prefix+directory+item['path']]
            self.assertEqual(hashlib.sha256(data).hexdigest(),item['sha256'])
        self.assertIn('完整回退流程',self.server.objects[prefix+directory+'GUIDE.txt'].decode())
        old_objects={p:b for p,b in self.server.objects.items() if '/baselines/' in p}
        # Deleting every rolling application/runtime object cannot break baseline.
        for p in list(self.server.objects):
            if '/backups/' in p or '/objects/runtime-' in p:del self.server.objects[p]
        for p,b in old_objects.items():self.assertEqual(self.server.objects[p],b)
        self.assertEqual(sum(m=='COPY' for m,p in self.server.calls),3)

    def test_baseline_copy_failure_keeps_original_pointer(self):
        for failure in ['unsupported','corrupt']:
            command=self.prepare_baseline();prefix='/dav/shellcrash-panel/K2P/'
            old=b'{"format":2,"label":"previous confirmed"}'
            self.server.objects[prefix+'baselines/baseline-latest.json']=old
            if failure=='unsupported':self.server.copy_status=405
            else:self.server.corrupt_get='/core.tar.gz'
            result=self.run_shell(command);self.assertNotEqual(result.returncode,0)
            self.assertEqual(self.server.objects[prefix+'baselines/baseline-latest.json'],old)
            self.server.copy_status=201;self.server.corrupt_get=''

    def test_uncertain_baseline_publication_keeps_previous_pointer(self):
        command=self.prepare_baseline();prefix='/dav/shellcrash-panel/K2P/baselines/'
        old=b'{"format":2,"label":"previous confirmed"}'
        self.server.objects[prefix+'baseline-latest.json']=old
        self.server.corrupt_baseline_after_move=True
        result=self.run_shell(command);self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.server.objects[prefix+'baseline-previous.json'],old)

    def test_baseline_slot_requires_explicit_replace_and_disabled_zero_requests(self):
        self.prepare_baseline();prefix='/dav/shellcrash-panel/K2P/'
        helper='. "$C/starts/backup-baseline.sh";baseline_check_slot '
        self.server.objects[prefix+'baselines/baseline-latest.json']=b'{}'
        self.assertEqual(self.run_shell(helper+'create').returncode,3)
        self.assertEqual(self.run_shell(helper+'replace').returncode,0)
        self.save(enabled='0');self.server.calls.clear()
        self.assertNotEqual(self.run_shell(helper+'replace').returncode,0)
        self.assertEqual(self.server.calls,[])

    def test_catalog_reads_independent_baseline_format_two(self):
        import json
        self.verify()
        record={'format':2,'scope':'full-application-baseline','sha256':'c'*64,'label':'working','core_version':'1.12.13'}
        self.server.objects['/dav/shellcrash-panel/K2P/baselines/baseline-latest.json']=json.dumps(record,separators=(',',':')).encode()
        result=json.loads(self.run_shell('dav_catalog').stdout)
        self.assertEqual(result['state'],'ready');self.assertEqual(json.loads(base64.b64decode(result['baseline_b64'])),record)

    def test_expected_core_can_restore_from_independent_baseline_without_changing_version(self):
        import json
        self.verify();core=b'current expected kernel';digest=hashlib.sha256(core).hexdigest()
        prefix='/dav/shellcrash-panel/K2P';index={'format':2,'core_sha256':digest,'path':'baselines/working-dbe/manifest.json', 'download':{'path':'baselines/working-dbe/full.zip'}}
        self.server.objects[prefix+'/baselines/baseline-latest.json']=json.dumps(index,separators=(',',':')).encode()
        self.server.objects[prefix+'/baselines/working-dbe/core.tar.gz']=core
        before=(self.root/'configs/core-installed.info').read_bytes()
        result=self.run_shell('remote_fetch core '+digest+' tar.gz "$D/restored" 1024')
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((self.root/'restored').read_bytes(),core)
        self.assertEqual((self.root/'configs/core-installed.info').read_bytes(),before)

    def test_old_remote_baseline_never_downgrades_new_installed_version(self):
        import json
        self.verify();old=b'old kernel';oldsha=hashlib.sha256(old).hexdigest();expected=hashlib.sha256(b'new kernel').hexdigest()
        prefix='/dav/shellcrash-panel/K2P';index={'format':2,'core_sha256':oldsha,'path':'baselines/working-old/manifest.json'}
        self.server.objects[prefix+'/baselines/baseline-latest.json']=json.dumps(index,separators=(',',':')).encode()
        old_path=prefix+'/baselines/working-old/core.tar.gz';self.server.objects[old_path]=old
        before=(self.root/'configs/core-installed.info').read_bytes();self.server.calls.clear()
        result=self.run_shell('remote_fetch core '+expected+' tar.gz "$D/restored" 1024')
        self.assertNotEqual(result.returncode,0);self.assertFalse((self.root/'restored').exists())
        self.assertNotIn(('GET',old_path),self.server.calls)
        self.assertEqual((self.root/'configs/core-installed.info').read_bytes(),before)

if __name__ == '__main__':
    unittest.main(verbosity=2)
