import os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class DirectDownloadTests(unittest.TestCase):
 def run_fixture(self,failed=False):
  td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup);p=Path(td.name);(p/'bin').mkdir();(p/'ram').mkdir()
  script=(ROOT/'ax5/direct-download.sh').read_text().replace('/tmp/ShellCrash/direct-download.',str(p/'ram')+'/direct-download.')
  (p/'run.sh').write_text(script)
  # Network/firewall tools are isolated. Test the real shell's cleanup control flow.
  lua=p/'bin/lua';lua.write_text('#!/bin/sh\ncase "$1:$2" in -:https:*) printf "subscription.example.com\\n443\\n";; *) printf "192.0.2.8\\n192.0.2.9\\n";; esac\n');lua.chmod(0o700)
  iptables=p/'bin/iptables';iptables.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_ROOT/firewall"\n');iptables.chmod(0o700)
  curl=p/'bin/curl';curl.write_text("""#!/usr/bin/env python3
import sys,os
from pathlib import Path
p=Path(os.environ['TEST_ROOT']);a=sys.argv[1:]
with (p/'requests').open('a') as f:f.write(' '.join(a)+'\\n')
if '--resolve' in a and os.environ.get('TEST_FAIL'):sys.exit(28)
Path(a[a.index('-o')+1]).write_text('fixture')
""");curl.chmod(0o700)
  env=dict(os.environ,PATH=str(p/'bin')+os.pathsep+os.environ['PATH'],TEST_ROOT=str(p))
  if failed:env['TEST_FAIL']='1'
  result=subprocess.run(['sh',str(p/'run.sh'),str(p/'output'),'https://subscription.example.com/private-token','Clash'],env=env,capture_output=True,text=True)
  return p,result
 def test_success_bypasses_only_resolved_root_tcp_destination_and_cleans(self):
  p,r=self.run_fixture();self.assertEqual(r.returncode,0,r.stderr)
  fw=(p/'firewall').read_text().splitlines();self.assertEqual(len(fw),2);self.assertIn('-I SC_AX5_OUT',fw[0]);self.assertIn('-D SC_AX5_OUT',fw[1]);self.assertIn('--uid-owner 0',fw[0]);self.assertIn('--dport 443',fw[0]);self.assertIn('-d 192.0.2.8',fw[0]);self.assertEqual(list((p/'ram').iterdir()),[])
  requests=(p/'requests').read_text().splitlines();self.assertNotIn('private-token',requests[0]);self.assertIn('--resolve subscription.example.com:443:192.0.2.8',requests[1]);self.assertNotIn('--insecure',requests[1])
 def test_failed_fetch_has_bounded_retries_and_removes_every_bypass(self):
  p,r=self.run_fixture(True);self.assertEqual(r.returncode,28,r.stderr);fw=(p/'firewall').read_text().splitlines();self.assertEqual(sum('-I 'in l for l in fw),2);self.assertEqual(sum('-D 'in l for l in fw),2);self.assertEqual(list((p/'ram').iterdir()),[])
if __name__=='__main__':unittest.main()
