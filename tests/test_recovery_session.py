import json
from pathlib import Path
import secrets
import shutil
import unittest
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime=None
ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(LuaRuntime,'Lua 5.1 test runtime unavailable')
class Session(unittest.TestCase):
    def setUp(self):
        self.x=Path('/tmp/sc-preflight-'+secrets.token_hex(4));self.x.mkdir(mode=0o700)
        self.time=100.0
        (self.x/'restore-worker.sh').write_text('#!/bin/sh\n# fixture')
        self.live=dict(operation_revision=1,pid=321,boot_id='fixture-boot',uptime=100,remote_fingerprint='a'*64,
                       config_fingerprint='b'*64,startup_fingerprint='c'*64,binary_sha256='d'*64,
                       core_sha256='e'*64,core_kind='singbox',core_version='1.12.13',binary_size=1000,
                       protect_mb=12,available_kb=24000,enabled=1,autostart=1,traffic_mode='rule')
        self.backup=dict(model='K2P',core_kind='singbox',core_version='1.12.13',files=[dict(name=n,path=n,size=200,sha256='e'*64 if n=='core.tar.gz'else'f'*64)for n in ['application.tar.gz','core.tar.gz','runtime-assets.tar.gz']])
        for name,value in [('live.json',self.live),('current.json',self.live),('backup.json',self.backup),
                           ('selection.json',dict(source='imports',prefix='imports/test/',manifest_path='imports/test/manifest.json',manifest_sha256='9'*64)),
                           ('application.json',dict(model='K2P',component='application',unpacked_size=1000,core_version='1.12.13',enabled=1,autostart=1,traffic_mode='rule')),
                           ('runtime.json',dict(model='K2P',component='runtime-assets',unpacked_size=1000)),
                           ('passed.json',dict(archive_checked=True,config_checked=True,core_checked=True))]:self.save(name,value)
    def tearDown(self):shutil.rmtree(self.x)
    def save(self,name,value):(self.x/name).write_text(json.dumps(value))
    def run_lua(self,action,token=None):
        lua=LuaRuntime()
        def plain(value):
            if hasattr(value,'items'):
                d=dict(value.items())
                if d and set(d)==set(range(1,len(d)+1)):return[plain(d[i])for i in range(1,len(d)+1)]
                return{k:plain(v)for k,v in d.items()}
            return value
        lua.globals()._decode=lambda raw:lua.table_from(json.loads(raw),recursive=True)
        lua.globals()._encode=lambda v:json.dumps(plain(v))
        lua.globals()._time=str(self.time)
        lua.execute('''package.preload.cjson=function()return {decode=_decode,encode=_encode}end
local original=io.open
io.open=function(p,mode)if p=='/proc/uptime'then return{read=function()return _time..' 0' end,close=function()end}end;return original(p,mode)end''')
        lua.globals().arg=lua.table_from([action,str(self.x)]+([token]if token else[]))
        lua.execute((ROOT/'shared/lib/recovery-session.lua').read_text())
    def arm(self):
        self.run_lua('plan');self.run_lua('finalize');self.run_lua('seal')
        return json.loads((self.x/'ticket.json').read_text())['token']
    def test_server_plan_has_native_budgets_and_single_use_ticket(self):
        token=self.arm();self.assertEqual(len(token),16)
        plan=(self.x/'plan').read_text();self.assertIn('application_path=imports/test/application.tar.gz',plan)
        self.assertIn('target_enabled=1',plan)
        self.run_lua('check',token);self.assertTrue((self.x/'ticket.json').exists())
        self.run_lua('take',token)
        with self.assertRaises(Exception):self.run_lua('take',token)
    def test_wrong_token_never_consumes_confirmation(self):
        token=self.arm()
        with self.assertRaises(Exception):self.run_lua('take','0'*16)
        self.run_lua('take',token)
    def test_expired_and_backwards_monotonic_time_rejected(self):
        for stamp in [99,281]:
            self.time=100;token=self.arm();self.time=stamp
            with self.assertRaises(Exception):self.run_lua('take',token)
        self.assertFalse((self.x/'ticket.json').exists())
    def test_modified_state_boot_core_remote_and_config_rejected(self):
        for field in ['operation_revision','pid','boot_id','remote_fingerprint','binary_sha256','core_sha256','config_fingerprint','enabled','autostart','traffic_mode','startup_fingerprint']:
            token=self.arm();self.save('current.json',{**self.live,field:'changed'})
            with self.subTest(field=field),self.assertRaises(Exception):self.run_lua('take',token)
            self.assertFalse((self.x/'ticket.json').exists())
        self.save('current.json',self.live);token=self.arm();self.run_lua('take',token)
    def test_changed_manifest_and_incomplete_native_results_rejected(self):
        token=self.arm();self.save('selection.json',dict(manifest_sha256='8'*64))
        with self.assertRaises(Exception):self.run_lua('take',token)
        self.save('passed.json',dict(archive_checked=True,config_checked=False,core_checked=True))
        with self.assertRaises(Exception):self.run_lua('seal')
    def test_modified_private_plan_or_worker_invalidates_ticket(self):
        for name in ['plan','restore-worker.sh']:
            token=self.arm()
            with (self.x/name).open('a')as f:f.write('\n# changed')
            with self.subTest(name=name),self.assertRaises(Exception):self.run_lua('take',token)
            self.assertFalse((self.x/'ticket.json').exists())
    def test_cross_version_wrong_archive_paths_and_low_memory_fail_closed(self):
        for delta in [dict(core_version='1.0'),dict(core_sha256='0'*64),dict(core_kind='meta')]:
            self.save('live.json',{**self.live,**delta})
            with self.subTest(delta=delta),self.assertRaises(Exception):self.run_lua('plan')
        self.save('live.json',self.live)
        for path in ['../escape','/absolute','imports/a/../b','https://external.invalid']:
            b=json.loads(json.dumps(self.backup));b['files'][0]['path']=path;self.save('backup.json',b)
            with self.assertRaises(Exception):self.run_lua('plan')
        self.save('backup.json',self.backup);self.run_lua('plan')
        self.save('live.json',{**self.live,'available_kb':13000})
        with self.assertRaises(Exception):self.run_lua('finalize')
if __name__=='__main__':unittest.main()
