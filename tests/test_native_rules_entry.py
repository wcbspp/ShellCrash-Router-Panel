"""Exercise both native menu wrappers and the real backend URL gate."""
from pathlib import Path
import json,os,re,shlex,subprocess,tarfile,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]

class NativeRulesEntry(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.c=self.root/'app';self.d=self.root/'state';self.d.mkdir();(self.c/'starts').mkdir(parents=True)
        (self.c/'libs').mkdir();(self.c/'libs/check_dir_avail.sh').write_text(':\n');(self.c/'libs/check_cpucore.sh').write_text(':\n');(self.c/'libs/web_get_bin.sh').write_text(':\n')
        self.bin=self.root/'bin';self.bin.mkdir();self.record=self.root/'calls.json'
        md5=self.bin/'md5sum';md5.write_text('#!/usr/bin/env python3\nimport sys,hashlib\nprint(hashlib.md5(sys.stdin.buffer.read()).hexdigest())\n');md5.chmod(0o700)
        self.env=dict(os.environ,PATH=str(self.bin)+':'+os.environ['PATH'],CRASHDIR=str(self.c),RULES_TEST_RECORD=str(self.record),RULES_TEST_PHASE=str(self.d/'phase'))

    def menu(self,profile):
        if profile=='k2p':text=(ROOT/'profiles/k2p/payload/menus/9_upgrade.sh').read_text()
        else:
            with tarfile.open(ROOT/'vendor/ShellCrash-1.9.4.tar.gz')as t:
                m=next(m for m in t.getmembers()if m.name.lstrip('./')=='menus/9_upgrade.sh');text=t.extractfile(m).read().decode()
            (self.root/'menus').mkdir(exist_ok=True);p=self.root/'menus/9_upgrade.sh';p.write_text(text)
            subprocess.run(['patch','-s','-p1','-i',str(ROOT/'profiles/ax5/tool-patches/menus-9_upgrade.sh.patch')],cwd=self.root,check=True,capture_output=True)
            text=p.read_text()
        text=text.replace('/etc/storage/ShellCrash',str(self.c)).replace('/data/ShellCrash',str(self.c)).replace('/tmp/sc-admin',str(self.d))
        p=self.root/'menu.sh';p.write_text(text);return p

    def shim(self,profile):
        if profile=='k2p':p=self.c/'starts/manage.sh'
        else:p=self.bin/'lua'
        p.write_text('''#!/usr/bin/env python3
import os,json,sys
from pathlib import Path
if sys.argv[1]=='-e':sys.exit(0 if Path(os.environ['RULES_TEST_PHASE']).read_text()=='done'else 1)
Path(os.environ['RULES_TEST_RECORD']).write_text(json.dumps(dict(args=sys.argv[1:],url=os.environ.get('SC_RULES_SOURCE_URL'))))
Path(os.environ['RULES_TEST_PHASE']).write_text(os.environ.get('RULES_TEST_RESULT','done'))
sys.exit(int(os.environ.get('RULES_TEST_EXIT','0')))
''');p.chmod(0o700)

    def invoke(self,profile,action='getgeo',name='cn_ip.txt',url='https://example.invalid/custom.txt',**env):
        # Each invocation gets its own temp menu path; no firmware command runs.
        menu=self.menu(profile);self.shim(profile)
        script='. '+shlex.quote(str(menu))+'\ngeoname='+shlex.quote(name)+';custgeolink='+shlex.quote(url)+'\ngetgeo_native(){ echo raw-default; };getcustgeo_native(){ echo raw-custom; };domain_update_wrap(){ "$1"; }\n'+action+'\n'
        return subprocess.run(['sh','-c',script],env=dict(self.env,**env),capture_output=True,text=True,timeout=10)

    def test_default_native_entry_uses_common_transaction(self):
        for profile in ['k2p','ax5']:
            with self.subTest(profile=profile):
                r=self.invoke(profile);self.assertEqual(r.returncode,0,r.stderr)
                call=json.loads(self.record.read_text())
                if profile=='k2p':self.assertEqual(call['args'][0],'rules');self.assertRegex(call['args'][1],r'^[a-f0-9]{8}$');url=call['url']
                else:self.assertTrue(call['args'][0].endswith('/rules-cli.lua'));url=call['args'][1]
                self.assertEqual(url,'https://ispip.clang.cn/all_cn.txt');self.assertNotIn('raw-',r.stdout)

    def test_custom_native_entry_passes_explicit_source(self):
        for profile in ['k2p','ax5']:
            r=self.invoke(profile,'getcustgeo');self.assertEqual(r.returncode,0,r.stderr)
            call=json.loads(self.record.read_text());self.assertEqual(call['url']if profile=='k2p'else call['args'][1],'https://example.invalid/custom.txt')

    def test_backend_error_is_not_reported_as_success(self):
        for profile in ['k2p','ax5']:
            r=self.invoke(profile,RULES_TEST_RESULT='error');self.assertNotEqual(r.returncode,0);self.assertNotIn('已通过',r.stdout)

    def test_other_database_entries_keep_their_native_path(self):
        for profile in ['k2p','ax5']:
            r=self.invoke(profile,name='cn.srs');self.assertEqual(r.returncode,0,r.stderr);self.assertIn('raw-default',r.stdout)

    def test_native_menu_displays_persisted_table_date_and_hash(self):
        import hashlib
        (self.c/'configs').mkdir(exist_ok=True);cfg=self.c/'configs/ShellCrash.cfg';cfg.write_text('')
        data=b'1.0.1.0/24\n';digest=hashlib.sha256(data).hexdigest()
        (self.c/'configs/cn_ip.txt').write_bytes(data);(self.c/'configs/rules-date').write_text('2026-10-16 stored')
        (self.c/'configs/rules.meta').write_text('1\n2026-10-16 stored\n'+digest+'\n')
        for profile in ['k2p','ax5']:
            menu=self.menu(profile);script='CFG_PATH='+shlex.quote(str(cfg))+';GeoIP_v=unrelated-upstream\n. '+shlex.quote(str(menu))+'\nsetgeo\n'
            r=subprocess.run(['sh','-c',script],input='0\n',env=self.env,capture_output=True,text=True,timeout=5);self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('2026-10-16 stored / '+digest[:12],r.stdout)

    def test_k2p_invalid_custom_urls_fail_before_configuration_or_network(self):
        source=(ROOT/'profiles/k2p/payload/starts/rules_update.sh').read_text()
        for url in ['http://example.invalid/rules','https://user:pass@example.invalid/rules','https://example.invalid/#fragment','https://host name/path','file:///etc/passwd']:
            script='set -e\nSC_RULES_SOURCE_URL='+shlex.quote(url)+'\nfail(){ echo "$1"; }\nrun(){\n'+source+'\n}\nrun\n'
            r=subprocess.run(['sh','-c',script],capture_output=True,text=True,timeout=5);self.assertNotEqual(r.returncode,0);self.assertIn('rules_invalid_source',r.stdout);self.assertNotIn('not found',r.stderr)

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime=None

@unittest.skipUnless(LuaRuntime,'Lua 5.1 runtime unavailable')
class AXNativeRulesDispatcher(unittest.TestCase):
    def run_cli(self,url,busy=False):
        lua=LuaRuntime();lua.execute('os.remove=function()return true end;saved={};writes={};locked=false;exec_called=false; M={C="/data/ShellCrash",R="/tmp/ShellCrash"};function M.lock()locked=true;return not busy end;function M.read()return "4"end;function M.write(k,v)writes[k]=v end;function M.save(k,v)saved[k]=v end;function M.b64(v)return v end;function dofile()return M end;package.preload.nixio=function()return {exec=function(...)exec_called=true;error("simulated exec")end}end')
        lua.globals().busy=busy;lua.globals().arg=lua.table_from([url])
        try:lua.execute((ROOT/'profiles/ax5/ax5/rules-cli.lua').read_text())
        except Exception:pass
        return lua

    def test_invalid_url_or_busy_lock_cannot_schedule_or_change_revision(self):
        for url in ['http://example.invalid/a','https://u:p@example.invalid/a','https://host/a#fragment','https://host name/a']:
            lua=self.run_cli(url);self.assertFalse(lua.globals().locked);self.assertFalse(lua.globals().exec_called);self.assertEqual(list(lua.globals().writes.items()),[])
        lua=self.run_cli('https://example.invalid/a',True);self.assertTrue(lua.globals().locked);self.assertEqual(list(lua.globals().saved.items()),[])

    def test_valid_native_request_uses_shared_job_and_invalidates_previous_ticket(self):
        lua=self.run_cli('https://example.invalid/a');self.assertTrue(lua.globals().exec_called)
        request=lua.globals().saved['/tmp/ShellCrash/request.json'];self.assertEqual(request.action,'rules');self.assertEqual(request.rules_url,'https://example.invalid/a');self.assertRegex(request.args[1],r'^[a-f0-9]{8}$')
        self.assertEqual(lua.globals().writes['/tmp/ShellCrash/recovery-revision'],'5')

if __name__=='__main__':unittest.main()
