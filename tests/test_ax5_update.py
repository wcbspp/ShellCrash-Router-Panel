"""Exercise AX5 source-only update and rollback in an isolated filesystem."""
import os,re,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class AX5UpdateTests(unittest.TestCase):
 def fixture(self,free=500,mem=18000,fail_copy=False,fail_sync=False):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td);pkg=r/'package';c=r/'data/ShellCrash';tool=r/'data/ShellCrash-tool';shim=r/'bin';shim.mkdir()
   for d in ['ax5','ui']:(pkg/d).mkdir(parents=True)
   (pkg/'tools').mkdir();(pkg/'tools/menu-install.lua').write_text('--fixture')
   for d in ['configs','ax5','ui','cache']:(c/d).mkdir(parents=True)
   tool.mkdir();(tool/'start.sh').write_text('fixture');(c/'configs/config.json').write_text('{"user":"unchanged"}');(c/'ax5/prepare.sh').write_text('old');(c/'ui/foo').write_text('old')
   for name in ['prepare.sh','controller.lua','view.htm']:(pkg/'ax5'/name).write_text('new')
   (pkg/'ax5/tool-sync.sh').write_text('#!/bin/sh\nexit '+('1' if fail_sync else '0')+'\n');(pkg/'ax5/tool-sync.sh').chmod(0o755)
   (pkg/'ax5/shellcrash.init').write_text('#!/bin/sh\necho "$1" >> '+str(r/'events')+'\n');(pkg/'ui/foo').write_text('new')
   for name in ['etc/init.d/shellcrash','usr/lib/lua/luci/controller/web/shellcrash.lua','usr/lib/lua/luci/view/web/shellcrash.htm','usr/lib/lua/luci/view/web/inc/header.htm','usr/bin/crash']:
    p=r/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('old')
   p=r/'usr/share/xiaoqiang/xiaoqiang_version';p.parent.mkdir(parents=True);p.write_text("HARDWARE 'RA67'\nROM '1.0.105'\n")
   (r/'proc').mkdir();(r/'proc/meminfo').write_text('MemAvailable: '+str(mem)+' kB\n');(r/'tmp').mkdir();(r/'overlay').mkdir()
   commands={'id':'echo 0','uname':'echo armv7l','lua':'exit 0','iptables':'exit 0','curl':'echo network >> '+str(r/'network')+';exit 1','stat':'''python3 -c 'import os,sys;print(os.stat(sys.argv[-1]).st_size)' "$@"''','df':'''echo 'fs size used available pct mounted'; echo 'fixture 29012 27000 '''+str(free)+''' 90% /data' '''}
   if fail_copy:commands['cp']='''for target;do :;done
case "$target" in '''+str(c)+'''/ui/foo.sc-new.*) printf partial > "$target";exit 1;; esac
exec /bin/cp "$@"'''
   for name,body in commands.items():
    p=shim/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
   script=(ROOT/'profiles/ax5/install.sh').read_text()
   script=re.sub(r'/(?:data/|etc/|usr/|tmp/|proc/|overlay)',lambda m:str(r)+m.group(0),script)
   script=script.replace('-C / ', '-C "'+str(r)+'" ').replace('-C / ||','-C "'+str(r)+'" ||')
   (pkg/'install.sh').write_text(script)
   env=os.environ.copy();env['PATH']=str(shim)+':'+env['PATH']
   result=subprocess.run(['sh',str(pkg/'install.sh'),'--update'],env=env,capture_output=True,text=True)
   self.assertEqual((c/'configs/config.json').read_text(),'{"user":"unchanged"}')
   return result,(c/'ui/foo').read_text(),list(c.rglob('*.sc-new.*')),(r/'network').exists(),(r/'events').read_text() if (r/'events').exists() else ''
 def test_small_flash_source_update_succeeds_without_core_start(self):
  result,marker,pending,network,events=self.fixture();self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertEqual(marker,'new');self.assertFalse(pending);self.assertFalse(network);self.assertEqual(events.strip(),'enable')
 def test_low_flash_and_low_ram_reject_before_writes(self):
  for args in [{'free':128},{'mem':15000}]:
   result,marker,pending,network,events=self.fixture(**args);self.assertNotEqual(result.returncode,0);self.assertEqual(marker,'old');self.assertFalse(pending);self.assertFalse(network);self.assertEqual(events,'')
 def test_partial_copy_and_late_failure_restore_source(self):
  for args in [{'fail_copy':True},{'fail_sync':True}]:
   result,marker,pending,network,_=self.fixture(**args);self.assertNotEqual(result.returncode,0);self.assertEqual(marker,'old',result.stdout+result.stderr);self.assertFalse(pending);self.assertFalse(network)
if __name__=='__main__':unittest.main()
