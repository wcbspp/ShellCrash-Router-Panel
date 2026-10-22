"""Run the actual Lua inventory against bounded lease/neighbour fixtures."""
from pathlib import Path
import unittest
try:
 from lupa.lua51 import LuaRuntime
except ImportError:
 LuaRuntime=None
ROOT=Path(__file__).resolve().parents[1]
@unittest.skipUnless(LuaRuntime,'Lua5.1 runtime unavailable; not a device pass')
class Inventory(unittest.TestCase):
 def inventory(self,arp):
  lua=LuaRuntime();lua.globals().lease='86400 02:11:22:33:44:55 192.168.1.20 MacBook *\n';lua.globals().arp=arp
  lua.execute('''arg={"list","/etc/storage/ShellCrash"};os.time=function()return 1700000000 end
package.preload.cjson=function()return{encode=function(t)captured=t;return "{}" end}end
io.open=function(path) local data=path=="/tmp/dnsmasq.leases" and lease or path=="/proc/net/arp" and arp or "";return{read=function()return data end,close=function()end}end
io.popen=function()return{read=function()return ""end,close=function()end}end
print=function()end''')
  lua.execute((ROOT/'shared/lib/access-devices.lua').read_text());result=lua.globals().captured
  return [] if result is None else [dict(result.devices[i]) for i in range(1,len(result.devices)+1)]
 def test_relative_or_old_lease_enriches_matching_live_neighbor(self):
  rows=self.inventory('192.168.1.20 0x1 0x2 02:11:22:33:44:55 * br0\n')
  self.assertEqual(rows[0]['name'],'MacBook');self.assertEqual(rows[0]['status'],'recent')
 def test_old_lease_alone_does_not_invent_current_device(self):
  self.assertEqual(self.inventory(''),[])
 def test_reused_address_with_other_mac_does_not_inherit_name(self):
  rows=self.inventory('192.168.1.20 0x1 0x2 02:66:77:88:99:aa * br0\n')
  self.assertEqual(rows[0]['name'],'')
