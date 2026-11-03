import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class AX5Audit(unittest.TestCase):
 def test_close_failure_is_not_success(self):
  source=(ROOT/'profiles/ax5/ax5/common.lua').read_text().splitlines()[3]
  lua=LuaRuntime(unpack_returned_tuples=True)
  ok=lua.execute('local M={}\n'+source+'''\nio.open=function()return {write=function()return true end,close=function()return nil,'disk full' end}end
   return pcall(M.write,'fixture','data')''')
  self.assertFalse(ok[0])
 def test_old_or_other_process_does_not_match(self):
  source=(ROOT/'profiles/ax5/ax5/state.lua').read_text()
  start=source.index(" local reason='unknown'");end=source.index(' local mem=M.memory()',start)
  lua=LuaRuntime(unpack_returned_tuples=True)
  fn=lua.execute('return function(text,pid,arg)\n'+source[start:end]+'return reason end')
  self.assertEqual(fn('[101.0] Killed process 42 (CrashCore)','42',lua.table_from({4:'100'})),'oom')
  self.assertEqual(fn('[99.0] Killed process 42 (CrashCore)','42',lua.table_from({4:'100'})),'unknown')
  self.assertEqual(fn('[101.0] Killed process 42 (other)','42',lua.table_from({4:'100'})),'unknown')
  self.assertEqual(fn('[101.0] Killed process 42 (CrashCore)','42',lua.table()),'unknown')
