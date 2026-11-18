"""A boot rule update must commit configuration and digest records together."""
import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BootTransaction(unittest.TestCase):
 def run_case(self,check=True,save=True,concurrent=False):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);p=Path(self.tmp.name)
  c=p/'c';d=p/'d'
  for x in [c/'starts',c/'configs',c/'jsons',d]:x.mkdir(parents=True,exist_ok=True)
  (c/'jsons/config.json').write_text('{"version":"old"}\n');(c/'configs/native-resources.tsv').write_text('old-manifest\n')
  (c/'starts/rule-source.sh').write_text((ROOT/'shared/lib/rule-source.sh').read_text())
  core=c/'core';core.write_text('#!/bin/sh\nexit '+('0' if check else '1')+'\n');core.chmod(0o700)
  persist=c/'starts/save_storage.sh';persist.write_text('''#!/bin/sh
n=$(cat "$C/saves" 2>/dev/null || echo 0);n=$((n+1));echo "$n" > "$C/saves"
[ "$FAIL_FIRST" != 1 ] || [ "$n" != 1 ]
''');persist.chmod(0o700)
  script='''. "$1"
rule_validation_binary(){ echo "$C/core"; }
native_resources_prepare(){ echo new-manifest > "$3";echo '{"version":"new"}' > "$2";[ "$CONCURRENT" != 1 ] || echo concurrent > "$C/jsons/config.json";return 0; }
native_resources_backup(){ :; }
native_clean_cache(){ :; }
logger(){ :; }
native_resources_recover
'''
  env=dict(os.environ,C=str(c),D=str(d),FAIL_FIRST='0' if save else '1',CONCURRENT='1' if concurrent else '0')
  r=subprocess.run(['sh','-c',script,'test',str(ROOT/'profiles/k2p/payload/starts/native_profile.sh')],env=env,capture_output=True,text=True,timeout=10)
  return r,c
 def test_checked_update_commits_matching_configuration_and_manifest(self):
  r,c=self.run_case();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('new',(c/'jsons/config.json').read_text());self.assertEqual((c/'configs/native-resources.tsv').read_text(),'new-manifest\n')
 def test_failed_core_check_cannot_change_configuration(self):
  r,c=self.run_case(check=False);self.assertNotEqual(r.returncode,0);self.assertIn('old',(c/'jsons/config.json').read_text());self.assertFalse((c/'saves').exists())
 def test_failed_storage_save_restores_and_repersists_both_originals(self):
  r,c=self.run_case(save=False);self.assertNotEqual(r.returncode,0);self.assertEqual((c/'jsons/config.json').read_text(),'{"version":"old"}\n');self.assertEqual((c/'configs/native-resources.tsv').read_text(),'old-manifest\n');self.assertEqual((c/'saves').read_text().strip(),'2')
 def test_concurrent_configuration_change_is_preserved(self):
  r,c=self.run_case(concurrent=True);self.assertNotEqual(r.returncode,0);self.assertEqual((c/'jsons/config.json').read_text(),'concurrent\n');self.assertFalse((c/'saves').exists())
if __name__=='__main__':unittest.main()
