import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime
SOURCE=(Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/state.lua').read_text()
class Scan(unittest.TestCase):
 def test_initialization_old_event_and_new_noncore_event(self):
  lua=LuaRuntime(unpack_returned_tuples=True)
  lua.execute('''
  files={['/proc/uptime']='100.0 0',['/proc/sys/kernel/random/boot_id']='boot'}
  records={};arg={'scan-oom'};kernel='[ 99.0] Killed process 7 (CrashCore)'
  M={C='/C',R='/R'}
  function M.read(p,n)return files[p]or''end
  function M.write(p,v)files[p]=v end
  function M.exec(c)return kernel end
  function M.load(p,d)return {records=records}end
  function dofile(p)if p=='/data/ShellCrash/ax5/common.lua'then return M end;return function(m,e)records={e}end end
  ''')
  lua.execute(SOURCE);self.assertEqual(lua.globals().files['/R/oom-scan-start'],'100.0')
  lua.execute(SOURCE);self.assertEqual(len(lua.globals().records),0)
  lua.globals().kernel='[ 101.0] Killed process 8 (lua)'
  lua.execute(SOURCE);self.assertEqual(lua.globals().records[1]['name'],'lua')
  self.assertEqual(lua.globals().records[1]['kernel_event'],'boot:101.0:8')
  lua.execute(SOURCE);self.assertEqual(len(lua.globals().records),1)
