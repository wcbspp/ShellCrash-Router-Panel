import json,subprocess,unittest
from pathlib import Path
from lupa.lua54 import LuaRuntime
SOURCE=(Path(__file__).resolve().parents[1]/'shared/lib/zerotier-compat.lua').read_text()
class Compat(unittest.TestCase):
 def test_ui_confirmation_and_result_states(self):
  subprocess.run(['node','tests/test_zerotier_compat_ui.js'],cwd=Path(__file__).resolve().parents[1],check=True,timeout=10)
 def fixture(self,raw='{"settings":{"portMappingEnabled":false}}'):
  L=LuaRuntime(unpack_returned_tuples=True)
  def convert(v):
   if isinstance(v,dict):return L.table_from({k:convert(x) for k,x in v.items()})
   if isinstance(v,list):return L.table_from([convert(x) for x in v])
   return v
  def plain(v):
   if hasattr(v,'items'):
    d={k:plain(x) for k,x in v.items()}
    if d and set(d)==set(range(1,len(d)+1)):return [d[i] for i in range(1,len(d)+1)]
    return d
   return v
  L.globals().decode=lambda s:convert(json.loads(s));L.globals().encode=lambda v:json.dumps(plain(v),ensure_ascii=False,separators=(',',':'))
  L.execute('''files={};types={};restarts=0;fail_restart=0;fail_rename=0;running=true;locked=false
M={C='/persist',R='/ram',json={decode=decode,encode=encode}}
function M.read(p,max)return (files[p]or''):sub(1,max or -1)end
function M.write(p,s)files[p]=s end
function M.load(p)local ok,v=pcall(decode,files[p]or'');return ok and v or {}end
function M.lock()return not locked end
function M.exec()return running and'123' or''end
function M.run(s)if s:find(' restart',1,true)then restarts=restarts+1;if fail_restart>0 then fail_restart=fail_restart-1;return false end end;return true end
os.remove=function(p)files[p]=nil;return true end
os.rename=function(a,b)if fail_rename>0 then fail_rename=fail_rename-1;return false end;files[b]=files[a];files[a]=nil;return true end
local fs={readlink=function(p)return files[p]end,lstat=function(p)if types[p]then return {type=types[p]}end;if files[p]then return{type='reg'}end end,chmod=function(p,mode)assert(mode=='600','native permission string required');return true end}
require=function(n)if n=='nixio.fs'then return fs elseif n=='nixio'then return{getpid=function()return123 end}end;error(n)end
dofile=function()return M end
files['/opt/etc/init.d/S27zerotier']='#!'
'''.replace('return123','return 123'))
  L.globals().files['/opt/var/lib/zerotier-one/local.conf']=raw
  L.execute("adapter={path='/opt/var/lib/zerotier-one/local.conf',prefix='utun',available=function()return true end,restart=function()return M.run('zerotier restart')end}")
  return L,L.execute(SOURCE,L.globals().M,L.globals().adapter)
 def test_running_instance_must_match_adapter_executable_and_home(self):
  L,Z=self.fixture();g=L.globals()
  g.adapter['binary']='/opt/bin/zerotier-one';g.adapter['home']='/opt/var/lib/zerotier-one'
  g.files['/proc/123/exe']='/opt/bin/zerotier-one'
  g.files['/proc/123/cmdline']='/opt/bin/zerotier-one\0-d\0/tmp/other-zerotier\0'
  self.assertFalse(Z.status().available)
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertIsNone(g.files['/persist/configs/zerotier-compat.json'])
  self.assertEqual(g.restarts,0)
  g.files['/proc/123/cmdline']='/opt/bin/zerotier-one\0-d\0/opt/var/lib/zerotier-one\0'
  self.assertTrue(Z.status().available)
  self.assertEqual(Z.status().config_path,'/opt/var/lib/zerotier-one/local.conf')
 def test_patch_preserves_unknown_bytes_and_types(self):
  raw=' { "outside":[], "settings" : {"portMappingEnabled":false,"empty":[],"nested":{"x":"a,}:b\\\"c"},"interfacePrefixBlacklist":["docker"]},"tail":{}} '
  L,Z=self.fixture(raw);new,added,had=Z.patch(raw,True,None)
  self.assertTrue(added and had)
  self.assertEqual(json.loads(new)['outside'],[])
  self.assertEqual(json.loads(new)['settings']['empty'],[])
  self.assertEqual(new.replace('["docker","utun"]','["docker"]'),raw)
 def test_enable_noop_and_exact_disable(self):
  raw=' {"outside":[], "settings" : { "portMappingEnabled" : false }} '
  L,Z=self.fixture(raw);self.assertTrue(Z.set(True,False));self.assertEqual(L.globals().restarts,1)
  self.assertFalse(Z.set(True,False));self.assertEqual(L.globals().restarts,1)
  self.assertTrue(Z.set(False,False));self.assertEqual(L.globals().restarts,2)
  self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw)
 def test_existing_user_exclusion_is_never_removed(self):
  raw='{"settings":{"interfacePrefixBlacklist":["utun","docker"]}}'
  L,Z=self.fixture(raw);Z.set(True,False);Z.set(False,False)
  self.assertEqual(L.globals().restarts,0);self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw)
 def test_external_changes_are_preserved_on_disable(self):
  L,Z=self.fixture();Z.set(True,False);f=L.globals().files;p='/opt/var/lib/zerotier-one/local.conf'
  f[p]=f[p].replace('false','true').replace('["utun"]','["utun","veth"]')
  Z.set(False,False);d=json.loads(f[p]);self.assertTrue(d['settings']['portMappingEnabled']);self.assertEqual(d['settings']['interfacePrefixBlacklist'],['veth'])
 def test_restart_failure_rolls_back(self):
  raw='{"settings":{"portMappingEnabled":false}}';L,Z=self.fixture(raw);L.globals().fail_restart=1
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw)
  self.assertIsNone(L.globals().files['/persist/configs/zerotier-compat.json']);self.assertEqual(L.globals().restarts,2)
 def test_unsafe_or_invalid_files_do_not_restart(self):
  for raw in ['[]','{"settings":null}','{"settings":[],"x":1}','{"settings":{"interfacePrefixBlacklist":{}}}','{"settings":{},"settings":{}}']:
   L,Z=self.fixture(raw)
   with self.assertRaises(Exception):Z.set(True,False)
   self.assertEqual(L.globals().restarts,0)
  L,Z=self.fixture();L.globals().types['/opt/var/lib/zerotier-one/local.conf']='lnk'
  with self.assertRaises(Exception):Z.set(True,False)
 def test_rename_failure_is_safe(self):
  raw='{"settings":{}}';L,Z=self.fixture(raw);L.globals().fail_rename=1
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw);self.assertEqual(L.globals().restarts,0)
 def test_deferred_lifecycle_and_stopped_service(self):
  L,Z=self.fixture();Z.set(True,False);f=L.globals().files;f['/opt/var/lib/zerotier-one/local.conf']='{"settings":{"portMappingEnabled":true}}'
  Z.enforce();self.assertEqual(L.globals().restarts,1);self.assertTrue(Z.status().pending)
  Z.finish();self.assertEqual(L.globals().restarts,2);self.assertFalse(Z.status().pending)
  Z.enforce();Z.finish();self.assertEqual(L.globals().restarts,2)
  L,Z=self.fixture();L.globals().running=False;Z.set(True,False);self.assertEqual(L.globals().restarts,0)
 def test_lock_is_respected(self):
  L,Z=self.fixture();L.globals().locked=True
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().restarts,0)
 def test_full_exclusion_list_and_corrupt_state_are_rejected(self):
  raw=json.dumps({'settings':{'interfacePrefixBlacklist':['veth'+str(i) for i in range(64)]}})
  L,Z=self.fixture(raw)
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw)
  self.assertEqual(L.globals().restarts,0)
 def test_volatile_config_recovers_and_restores_absence(self):
  L,Z=self.fixture();f=L.globals().files;p='/opt/var/lib/zerotier-one/local.conf'
  L.globals().adapter.allow_missing=True;f[p]=None
  self.assertTrue(Z.status().available);Z.set(True,False)
  applied=f[p];self.assertIn('utun',applied)
  f[p]=None;Z.enforce();self.assertEqual(f[p],applied);self.assertTrue(Z.status().pending)
  Z.finish();Z.set(False,False);self.assertIsNone(f[p])
 def test_persistence_failure_restores_config_and_policy(self):
  raw='{"settings":{"portMappingEnabled":false}}';L,Z=self.fixture(raw)
  L.execute('persist_calls=0;adapter.persist=function()persist_calls=persist_calls+1;return persist_calls>1 end')
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().files['/opt/var/lib/zerotier-one/local.conf'],raw)
  self.assertIsNone(L.globals().files['/persist/configs/zerotier-compat.json'])
  self.assertEqual(L.globals().persist_calls,2)
  L,Z=self.fixture();L.globals().files['/persist/configs/zerotier-compat.json']='{"enabled":true}'
  self.assertFalse(Z.status().available)
  with self.assertRaises(Exception):Z.set(True,False)
  self.assertEqual(L.globals().restarts,0)
