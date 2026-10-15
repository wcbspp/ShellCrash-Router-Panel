"""Run the shipped Lua parser with real gzip streams; no tar parser mock."""
import gzip
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(LuaRuntime, 'Lua 5.1 test runtime (lupa) unavailable; firmware checks are separate')
class NativeArchive(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)/'archive.tar.gz'
        self.hash = 'a'*64
        self.app = {
            'backup.info': b'model=K2P\nenabled=1\nautostart=1\ntraffic_mode=rule\n',
            'start.sh': b'fixture', 'menu.sh': b'fixture', 'menus/bot_tg_service.sh': b'fixture',
            'starts/panel_boot.sh': b'fixture', 'configs/ShellCrash.cfg': b'core=singbox',
            'configs/core-installed.info': ('arch=mipsle-softfloat\nversion=1.12.13\nsha256='+self.hash+'\n').encode(),
            'jsons/config.json': b'{"outbounds":[{"type":"direct"}]}',
        }

    def tearDown(self):
        self.tmp.cleanup()

    def pack(self, files):
        with tarfile.open(self.path, 'w:gz', format=tarfile.USTAR_FORMAT) as tar:
            for name, data in files:
                if isinstance(data, tarfile.TarInfo):
                    tar.addfile(data)
                else:
                    info = tarfile.TarInfo(name)
                    info.mode = 0o700
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))

    def run_parser(self, component='application', model='K2P'):
        lua = LuaRuntime(encoding=None)
        def table(value):
            if isinstance(value, dict): return lua.table_from({k.encode(): table(v) for k,v in value.items()})
            if isinstance(value, list): return lua.table_from([table(v) for v in value])
            return value.encode() if isinstance(value, str) else value
        def plain(value):
            if isinstance(value, bytes): return value.decode()
            if hasattr(value, 'items'): return {plain(k): plain(v) for k,v in value.items()}
            return value
        lua.globals()._decode = lambda raw: table(json.loads(raw))
        lua.globals()._encode = lambda obj: json.dumps(plain(obj)).encode()
        # Lupa disables popen at compile time. This adapter runs the exact gzip
        # subprocess and exposes its actual bytes/status to the shipped parser.
        children = []
        def popen(cmd):
            child = subprocess.Popen(cmd.decode(), shell=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            children.append(child)
            return child
        lua.globals()._popen = popen
        lua.globals()._read = lambda child,n: child.stdout.read(n) or None
        def close(child):
            child.stdout.close()
            return child.wait(timeout=5)
        lua.globals()._close = close
        lua.execute(b'''package.preload.cjson=function()return {decode=_decode,encode=_encode}end
io.popen=function(cmd) local p=_popen(cmd);return {read=function(self,n)return _read(p,n)end,close=function()return _close(p)end}end
print=function(v) _result=v end''')
        lua.globals().arg = table([component, str(self.path), self.hash, model])
        try:
            lua.execute((ROOT/'shared/lib/restore-archive.lua').read_bytes())
            return json.loads(lua.globals()._result)
        finally:
            for child in children:
                if child.poll() is None: child.kill(); child.wait()

    def test_complete_native_k2p_metadata_and_no_extraction(self):
        self.pack(self.app.items())
        result = self.run_parser()
        self.assertEqual(result['core_version'], '1.12.13')
        self.assertEqual(result['enabled'], 1)
        self.assertEqual(result['unpacked_size'], sum(map(len,self.app.values())))
        self.assertEqual(list(Path(self.tmp.name).iterdir()), [self.path])

    def test_missing_menu_old_start_state_wrong_core_and_duplicate_metadata_rejected(self):
        changes = [('menus/bot_tg_service.sh', None), ('backup.info', b'model=K2P\n'),
                   ('configs/core-installed.info', b'arch=mips\n'),
                   ('backup.info', self.app['backup.info']+b'enabled=0\n'),
                   ('jsons/config.json', b'{broken'), ('jsons/config.json', b'{"outbounds":[]}')]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                files = {**self.app}
                if value is None: del files[key]
                else: files[key] = value
                self.pack(files.items())
                with self.assertRaises(Exception): self.run_parser()

    def test_traversal_absolute_duplicate_credentials_and_file_parents_rejected(self):
        extras = [[('../outside',b'x')], [('/etc/passwd',b'x')], [('configs//x',b'x')],
                  [('configs/x\\evil',b'x')], [('configs/webdav.auth',b'x')],
                  [('start.sh',b'duplicate')], [('configs/parent',b'x'),('configs/parent/child',b'x')],
                  [('configs/parent/child',b'x'),('configs/parent',b'x')]]
        for extra in extras:
            with self.subTest(extra=extra):
                self.pack(list(self.app.items())+extra)
                with self.assertRaises(Exception): self.run_parser()

    def test_links_special_files_permissions_and_required_directory_rejected(self):
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE, tarfile.DIRTYPE]:
            with self.subTest(kind=kind):
                files = {**self.app};del files['menus/bot_tg_service.sh']
                info = tarfile.TarInfo('menus/bot_tg_service.sh');info.type=kind;info.linkname='/etc/passwd'
                self.pack(list(files.items())+[('',info)])
                with self.assertRaises(Exception): self.run_parser()
        self.pack(self.app.items())
        raw=bytearray(gzip.decompress(self.path.read_bytes()));raw[100:108]=b'0004700\0';raw[148:156]=b'        '
        raw[148:156]=('%06o\0 ' % sum(raw[:512])).encode();self.path.write_bytes(gzip.compress(raw))
        with self.assertRaises(Exception): self.run_parser()

    def test_crc_truncation_checksum_trailing_data_and_expansion_limit_rejected(self):
        self.pack(self.app.items());original=self.path.read_bytes();raw=gzip.decompress(original)
        corrupt=bytearray(original);corrupt[-8]^=1
        for body in [bytes(corrupt), original[:-20], gzip.compress(b'bad'+raw[3:]),
                     gzip.compress(raw+b'x'*512), gzip.compress(raw+b'\0'*16000000)]:
            with self.subTest(size=len(body)):
                self.path.write_bytes(body)
                with self.assertRaises(Exception): self.run_parser()

    def test_runtime_roots_are_profile_specific(self):
        self.pack([('ShellCrash/ruleset/cn.srs',b'fixture'),('ShellCrash-dashboard/index.html',b'fixture')])
        self.assertEqual(self.run_parser('runtime-assets')['members'],2)
        with self.assertRaises(Exception): self.run_parser('runtime-assets','AX5')
        self.pack([('ShellCrash/configs/config.json',b'{}')])
        with self.assertRaises(Exception): self.run_parser('runtime-assets')

    def test_core_architecture_and_only_member_checked(self):
        elf=bytearray(128);elf[:6]=b'\x7fELF\x01\x01';elf[18]=8
        self.pack([('CrashCore',elf)])
        self.assertEqual(self.run_parser('core')['unpacked_size'],128)
        with self.assertRaises(Exception): self.run_parser('core','AX5')
        self.pack([('CrashCore',elf),('extra',b'bad')])
        with self.assertRaises(Exception): self.run_parser('core')

    def test_existing_ax5_metadata_remains_supported(self):
        files={'backup.info':b'model=AX5\n','configs/config.json':b'{}','configs/enabled':b'1\n',
               'cache/core.env':('HASH="'+self.hash+'"\n').encode(), 'ax5/api.lua':b'fixture',
               'ax5/prepare.sh':b'fixture','ax5/shellcrash.init':b'fixture',
               'ShellCrash-tool/configs/ShellCrash.cfg':b'fixture'}
        self.pack(files.items())
        self.assertEqual(self.run_parser(model='AX5')['model'],'AX5')


class NativeDownload(unittest.TestCase):
    def test_real_lengthless_oversize_and_truncated_bodies_are_bounded(self):
        import http.server
        import threading
        import shlex
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body=b'x'*(4096 if self.path=='/valid' else 100000 if self.path=='/oversize' else 100)
                self.send_response(200)
                if self.path=='/truncated': self.send_header('Content-Length','4096')
                self.end_headers()
                try: self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError): pass
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        source=(ROOT/'profiles/k2p/payload/starts/restore-preflight.sh').read_text()
        function=source[source.index('download(){'):source.index('\n# Downloads are bounded')]
        # macOS exposes inherited descriptors under /dev/fd; firmware uses /proc.
        if not Path('/proc/self/fd').exists(): function=function.replace('/proc/self/fd/3','/dev/fd/3')
        try:
            with tempfile.TemporaryDirectory() as tmp:
                for route in ['valid','oversize','short','truncated']:
                    script='set -e\nX='+shlex.quote(tmp)+'\ndav_curl(){ curl -sS "$@"; }\n'+function
                    script+='\ndownload http://127.0.0.1:'+str(server.server_port)+'/'+route+' 4096 "$X/body"\n'
                    r=subprocess.run(['sh','-c',script],capture_output=True,timeout=10)
                    self.assertEqual(r.returncode==0,route=='valid',r.stderr)
                    self.assertLessEqual((Path(tmp)/'body').stat().st_size,4097)
        finally:
            server.shutdown();server.server_close();thread.join()


@unittest.skipUnless(LuaRuntime, 'Lua 5.1 test runtime unavailable')
class NativeConfig(unittest.TestCase):
    def setUp(self):
        import secrets
        self.root = Path('/tmp/sc-preflight-'+secrets.token_hex(4))
        self.root.mkdir(mode=0o700)
        (self.root/'runtime/ShellCrash/ruleset').mkdir(parents=True)
        (self.root/'runtime/ShellCrash/ruleset/cn.srs').write_bytes(b'fixture')

    def tearDown(self):
        import shutil
        shutil.rmtree(self.root)

    def run_config(self,config):
        (self.root/'config.original.json').write_text(json.dumps(config))
        lua=LuaRuntime()
        def convert(v):
            if hasattr(v,'items'):
                items=dict(v.items())
                if items and set(items)==set(range(1,len(items)+1)): return [convert(items[i]) for i in range(1,len(items)+1)]
                return {k:convert(x) for k,x in items.items()}
            return v
        lua.globals()._decode=lambda raw:lua.table_from(json.loads(raw),recursive=True)
        lua.globals()._encode=lambda value:json.dumps(convert(value))
        lua.execute('package.preload.cjson=function()return {decode=_decode,encode=_encode}end')
        lua.globals().arg=lua.table_from([str(self.root)])
        lua.execute((ROOT/'profiles/k2p/payload/starts/restore-config.lua').read_text())
        return json.loads((self.root/'config.check.json').read_text())

    def test_rule_paths_and_writable_files_are_isolated_websocket_path_preserved(self):
        original=dict(outbounds=[dict(type='vmess',transport=dict(type='ws',path='/proxy'))],
                      route=dict(rule_set=[dict(type='local',path='/tmp/ShellCrash/ruleset/cn.srs')]),
                      log=dict(output='/tmp/ShellCrash/service.log'),
                      experimental=dict(cache_file=dict(enabled=True,path='/tmp/ShellCrash/cache.db'),
                                        clash_api=dict(external_ui='/tmp/ShellCrash-dashboard')))
        result=self.run_config(original)
        self.assertTrue(result['route']['rule_set'][0]['path'].startswith(str(self.root)))
        self.assertEqual(result['outbounds'][0]['transport']['path'],'/proxy')
        self.assertFalse(result['experimental']['cache_file']['enabled'])
        self.assertTrue(result['log']['output'].startswith(str(self.root)))
        self.assertEqual(json.loads((self.root/'config.original.json').read_text()),original)

    def test_remote_rules_missing_files_traversal_and_external_keys_rejected(self):
        for value in [dict(type='remote',url='https://example.invalid/rules.srs'),
                      dict(type='local',path='/tmp/ShellCrash/ruleset/missing.srs'),
                      dict(type='local',path='/tmp/ShellCrash/ruleset/../secret'),
                      dict(key_path='/etc/secret')]:
            with self.subTest(value=value),self.assertRaises(Exception):
                self.run_config(dict(outbounds=[dict(type='direct')],route=dict(rule_set=[value])))

if __name__=='__main__': unittest.main()
