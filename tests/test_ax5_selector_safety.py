import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime, LuaError

SOURCE = (Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/state.lua').read_text()

class SelectorSafety(unittest.TestCase):
 def setup_lua(self, action, status=200):
  lua=LuaRuntime(unpack_returned_tuples=True)
  lua.execute('''
  saved={}; writes={}; applied=false; status=200
  M={C='/C',R='/R',json={}}
  function M.json.decode(s) return {proxies={group={type='Selector',now=applied and 'chosen' or 'default',all={'default','chosen'}}}} end
  function M.json.encode(v)return '{}'end
  function M.read(p) if p=='/proc/uptime' then return '100.0' end;if p=='/R/service-ready' then return '1\\n' end;return '' end
  function M.load(p,d) if p=='/R/job.json' then return {active=true} end;if p=='/R/selectors.json' or p=='/C/configs/selectors.json' then return {group='chosen'} end;return d or {} end
  function M.save(p,v)saved[p]=v end;function M.write(p,v)writes[p]=v end
  function M.memory()return {MemAvailable=30000}end;function M.trimlogs()end
  function M.state()return {running=true,pid=1,rss_kb=1,available_kb=30000,conntrack=1,memory_limits={cleanup_mb=0}}end
  function M.lock(name) return name=='sample.lock' end
  function M.pid()return 1 end
  function M.api()return '{}'end
  function M.request(path,method)if method then applied=status==200;return '',status end;return '{}',200 end
  function dofile()return M end
  ''')
  lua.globals().status=status;lua.globals().arg=lua.table_from([action]);return lua
 def test_busy_operation_does_not_save_default_selection(self):
  lua=self.setup_lua('sample');lua.execute(SOURCE)
  self.assertIsNone(lua.globals().saved['/C/configs/selectors.json'])
 def test_failed_selection_restore_fails(self):
  lua=self.setup_lua('restore',503)
  with self.assertRaises(LuaError):lua.execute(SOURCE)
 def test_successful_restore_is_verified(self):
  lua=self.setup_lua('restore',200);lua.execute(SOURCE)
  self.assertTrue(lua.globals().applied)

class StartupSafety(unittest.TestCase):
 def test_unready_core_is_terminated(self):
  import subprocess
  src=(Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/run.sh').read_text()
  block=src.split('ready=0\nfor i in',1)[1].split('wait "$child"',1)[0]
  script='''child=99;ending=0;curl(){ return 1; }; sleep(){ :; }; kill(){ if [ "$1" = -TERM ];then echo terminated;fi;return 0; }
ready=0
for i in'''+block
  result=subprocess.run(['sh','-c',script],capture_output=True,text=True,check=True)
  self.assertIn('terminated',result.stdout)
