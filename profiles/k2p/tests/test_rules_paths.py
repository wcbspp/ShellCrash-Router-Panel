#!/usr/bin/env python3
"""Domestic rules survive missing SSR/custom paths and preserve manual updates."""
import os, subprocess, tempfile, unittest, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class RulePathsTests(unittest.TestCase):
 def fixture(self,d):
  c=d/'ShellCrash';(c/'configs').mkdir(parents=True);(c/'starts').mkdir();(c/'jsons').mkdir()
  (c/'configs/cn_ip.default.txt').write_bytes((ROOT/'examples/cn_ip.default.txt').read_bytes())
  (c/'starts/rules_validate.awk').write_bytes((ROOT/'payload/starts/rules_validate.awk').read_bytes())
  script=d/'rules_path.sh';script.write_text((ROOT/'payload/starts/rules_path.sh').read_text().replace('/etc/storage/chinadns/chnroute.txt',str(d/'missing-ssr/chnroute.txt')))
  (c/'jsons/config.json').write_text('{\n"route":{"rules":[{"ip_cidr":["1.0.1.0/24"],"outbound":"direct"}]},\n"outbounds":[{"type":"direct","tag":"direct"}]\n}\n')
  return c,script
 def ensure(self,c,script,custom=''):
  r=subprocess.run(['sh','-c','C="$1"; PANEL_CN_IP_FILE="$3"; . "$2"; rules_ensure; status=$?; echo "$RULES_FILE"; exit "$status"','test',str(c),str(script),custom],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stdout+r.stderr)
  return (c/'configs/cn_ip.txt').read_bytes()
 def test_no_old_plugin_directory_uses_frozen_default(self):
  with tempfile.TemporaryDirectory() as td:
   c,s=self.fixture(Path(td));data=self.ensure(c,s)
   self.assertEqual(data,(ROOT/'examples/cn_ip.default.txt').read_bytes());self.assertTrue((c/'configs/rules.meta').is_file())
   obj=json.loads((c/'jsons/config.json').read_text());self.assertEqual(len(obj['route']['rules'][0]['ip_cidr']),4507)
 def test_missing_custom_path_falls_back_without_error(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c,s=self.fixture(d);self.ensure(c,s,str(d/'does-not-exist/table.txt'))
 def test_alternative_path_is_imported_and_updates_preserved(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c,s=self.fixture(d);custom=d/'other/table.txt';custom.parent.mkdir();data=(ROOT/'examples/cn_ip.default.txt').read_bytes()+b'8.8.8.0/24\n';custom.write_bytes(data)
   self.assertEqual(self.ensure(c,s,str(custom)),data)
   custom.unlink();(c/'configs/rules.meta').unlink()
   self.assertEqual(self.ensure(c,s,str(custom)),data);self.assertEqual((c/'configs/rules.meta').read_text().splitlines()[0],'4508')
 def test_invalid_import_is_skipped(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c,s=self.fixture(d);custom=d/'bad.txt';custom.write_text('192.168.0.0/16\n')
   self.assertEqual(self.ensure(c,s,str(custom)),(ROOT/'examples/cn_ip.default.txt').read_bytes())
if __name__=='__main__':unittest.main(verbosity=2)
