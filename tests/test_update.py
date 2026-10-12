import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class UpdateTests(unittest.TestCase):
 def fixture(self,mode,fail_save=False,fail_api=False,busy=False,mem=24000,unknown=False):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);c=root/'storage/ShellCrash';d=root/'state';base=root/'package';shim=root/'bin';shim.mkdir();d.mkdir();(base/'tools').mkdir(parents=True)
   (c/'configs').mkdir(parents=True);(c/'configs/panel.conf').write_text('fixture\n');(c/'configs/ShellCrash.cfg').write_text('crashcore=singbox\nsecret=fixture-only\n');(c/'version').write_text('1.9.4release\n');(c.parent/'started_script.sh').write_text('#PadavanShellCrashPanel\n')
   for part in ['starts','libs','menus','padavan','ui']:
    (c/part).mkdir();(base/'payload'/part).mkdir(parents=True);(c/part/'marker').write_text('old');(base/'payload'/part/'marker').write_text('new')
   (c/'starts/panel_boot.sh').write_text('#!/bin/sh\nexit 0\n');(c/'padavan/manager.js').write_text('old')
   helpers={'padavan_ui.sh':'exit 0','save_storage.sh':'exit 0'}
   for name,body in helpers.items():
    for place in [c/'starts',base/'payload/starts']:
     f=place/name;f.write_text('#!/bin/sh\n'+body+'\n');f.chmod(0o700)
   if fail_save:(base/'payload/starts/save_storage.sh').write_text('#!/bin/sh\nexit 1\n')
   commands={'id':'echo 0','nvram':'echo 192.168.1.1','pidof':'echo 123','curl':'exit '+('1' if fail_api else '0')}
   for name,body in commands.items():
    f=shim/name;f.write_text('#!/bin/sh\n'+body+'\n');f.chmod(0o700)
   if busy:(d/'operation.lock').mkdir()
   if unknown:(c/'version').write_text('other\n')
   memfile=root/'meminfo';memfile.write_text('MemAvailable: '+str(mem)+' kB\n')
   script=(ROOT/'profiles/k2p/tools/update.sh').read_text().replace('C=/etc/storage/ShellCrash','C='+str(c)).replace('D=/tmp/sc-admin','D='+str(d)).replace('/etc/storage/started_script.sh',str(c.parent/'started_script.sh')).replace('/proc/meminfo',str(memfile)).replace('/tmp/shellcrash-bootstrap.lock',str(root/'bootstrap.lock')).replace('/tmp/sc-upgrade.XXXXXX',str(root/'upgrade.XXXXXX'))
   (base/'tools/update.sh').write_text(script);before=(c/'configs/ShellCrash.cfg').read_bytes()
   env=os.environ.copy();env['PATH']=str(shim)+':'+env['PATH'];result=subprocess.run(['sh',str(base/'tools/update.sh'),mode],env=env,capture_output=True,text=True)
   markers=[(c/part/'marker').read_text() for part in ['starts','libs','menus','padavan','ui']]
   self.assertEqual((c/'configs/ShellCrash.cfg').read_bytes(),before)
   return result,markers,(d/'operation.lock').exists()
 def test_check_never_modifies(self):
  r,m,lock=self.fixture('--check');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(m,['old']*5);self.assertFalse(lock)
 def test_update_preserves_config_and_releases_lock(self):
  r,m,lock=self.fixture('--apply');self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertEqual(m,['new']*5);self.assertFalse(lock)
 def test_save_failure_rolls_back_code(self):
  r,m,lock=self.fixture('--apply',fail_save=True);self.assertNotEqual(r.returncode,0);self.assertEqual(m,['old']*5);self.assertFalse(lock)
 def test_api_failure_rolls_back_code(self):
  r,m,lock=self.fixture('--apply',fail_api=True);self.assertNotEqual(r.returncode,0);self.assertEqual(m,['old']*5);self.assertFalse(lock)
 def test_busy_low_memory_unknown_tool_reject_before_copy(self):
  for args in [{'busy':True},{'mem':13000},{'unknown':True}]:
   r,m,_=self.fixture('--apply',**args);self.assertNotEqual(r.returncode,0);self.assertEqual(m,['old']*5)
if __name__=='__main__':unittest.main()
