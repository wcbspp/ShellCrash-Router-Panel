import os,shutil,subprocess,tempfile,unittest
from pathlib import Path
SCRIPT=Path(__file__).resolve().parents[1]/'shared/lib/backup-links.sh'
class PortableBackupLinks(unittest.TestCase):
 def test_ax5_generated_aliases_are_omitted(self):
  with tempfile.TemporaryDirectory() as td:
   stage=Path(td);(stage/'ShellCrash-tool/jsons').mkdir(parents=True);(stage/'ShellCrash-tool/yamls').mkdir(parents=True);(stage/'configs').mkdir();canonical=stage/'configs/config.json';canonical.write_text('fixture')
   for name,target in [('jsons/config.json','/data/ShellCrash/configs/config.json'),('yamls/config.yaml','/data/ShellCrash/configs/config.yaml')]: (stage/'ShellCrash-tool'/name).symlink_to(target)
   subprocess.run(['sh',str(SCRIPT),str(stage),'ax5'],check=True);self.assertEqual(canonical.read_text(),'fixture');self.assertEqual(list(stage.rglob('config.yaml')),[]);self.assertFalse((stage/'ShellCrash-tool/jsons/config.json').is_symlink())
 def test_k2p_minimal_path_without_readlink(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);stage=root/'stage';(stage/'jsons').mkdir(parents=True);link=stage/'jsons/dns.json';link.symlink_to('/tmp/panel-dns/dns.json');binpath=root/'bin';binpath.mkdir()
   for name in ['find','ls','sed','rm']:(binpath/name).symlink_to(shutil.which(name))
   subprocess.run(['/bin/sh',str(SCRIPT),str(stage),'k2p'],env={**os.environ,'PATH':str(binpath)},check=True);self.assertFalse(link.is_symlink())
 def test_arbitrary_link_is_rejected_without_following_it(self):
  with tempfile.TemporaryDirectory() as td:
   stage=Path(td);link=stage/'ui.js';link.symlink_to('/etc/passwd');r=subprocess.run(['sh',str(SCRIPT),str(stage),'ax5'],capture_output=True);self.assertNotEqual(r.returncode,0);self.assertTrue(link.is_symlink())
if __name__=='__main__':unittest.main()
