import tempfile, unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime, LuaError
SOURCE=(Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/oom-record.lua').read_text()
class Persistence(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.dir=Path(self.tmp.name);(self.dir/'configs').mkdir();self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().directory=str(self.dir)
  self.lua.execute('''
   available=800; rename_ok=true
   oldrename=os.rename;os.rename=function(a,b)if not rename_ok then return nil end;return oldrename(a,b)end
   M={C=directory,R=directory,json={}}
   package.preload['nixio']=function()return {getpid=function()return 1 end}end
   lock_ok=true
   function M.lock(n)if not lock_ok then return false end;return os.execute('mkdir '..directory..'/'..n)==0 end
   function M.exec()return tostring(available)end
   function M.run()return true end
   function M.read(p,n)local f=io.open(p,'rb');if not f then return '' end;local s=f:read(n);f:close();return s or '' end
   function M.write(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));assert(f:close())end
   function M.json.encode(x)local a={};for _,v in ipairs(x.records)do a[#a+1]=v.id end;return table.concat(a,'|')end
   function M.json.decode(s)if s=='corrupt' then error('bad JSON')end;local a={};for x in s:gmatch('[^|]+')do a[#a+1]={id=x,time='time',pid='1'}end;return {records=a}end
  ''')
  self.save=self.lua.execute(SOURCE)
 def write(self,id):self.save(self.lua.globals().M,self.lua.table_from({'id':id}))
 def read(self):return (self.dir/'configs/oom-records.json').read_text()
 def test_keeps_latest_one(self):
  for s in ('a','b','c'):self.write(s)
  self.assertEqual(self.read(),'c')
 def test_low_space_preserves_both(self):
  self.write('a');self.write('b');self.lua.globals().available=639
  with self.assertRaises(LuaError):self.write('c')
  self.assertEqual(self.read(),'b')
 def test_rename_failure_preserves_previous(self):
  self.write('a');self.write('b');self.lua.globals().rename_ok=False
  with self.assertRaises(LuaError):self.write('c')
  self.assertEqual(self.read(),'b')

 def test_busy_writer_preserves_previous(self):
  self.write('a');self.lua.globals().lock_ok=False
  with self.assertRaises(LuaError):self.write('b')
  self.assertEqual(self.read(),'a')
 def test_corrupt_previous_is_not_overwritten(self):
  target=self.dir/'configs/oom-records.json';target.write_text('corrupt')
  with self.assertRaises(LuaError):self.write('c')
  self.assertEqual(self.read(),'corrupt')
