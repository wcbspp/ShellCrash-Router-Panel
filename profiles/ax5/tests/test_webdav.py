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

SOURCE = Path(__file__).resolve().parents[1] / 'ax5'
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
        if self.command == 'OPTIONS':
            status = 200
        elif self.command == 'MKCOL':
            status = 201
        elif self.command == 'PUT':
            objects[self.path] = self.rfile.read(int(self.headers['Content-Length']))
            status = 201
        elif self.command == 'GET':
            status = 200 if self.path in objects else 404
            body = objects.get(self.path, b'')
        elif self.command == 'DELETE':
            objects.pop(self.path, None)
        elif self.command == 'MOVE':
            from urllib.parse import urlsplit
            objects[urlsplit(self.headers['Destination']).path] = objects.pop(self.path)
        self.send_response(status); self.send_header('Content-Length', str(len(body))); self.end_headers()
        self.wfile.write(body)
    do_GET = do_PUT = do_MKCOL = do_DELETE = do_MOVE = do_OPTIONS = handle_request

class WebDAV(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root/'configs').mkdir(); (self.root/'starts').mkdir(); (self.root/'ax5').mkdir()
        (self.root/'version').write_text('1.9.4release')
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
        self.assertEqual(index['sha256'], digests[1]); self.assertEqual(index['tool_version'], '1.9.4release')
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

if __name__ == '__main__':
    unittest.main(verbosity=2)
