import json, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'shared/lib/subscription-quota.sh').read_text()
AWK=SOURCE.split('head -c 8192 | awk -v checked="$(date +%s)" \'',1)[1].split("' > ",1)[0]
class QuotaTests(unittest.TestCase):
 def parse(self, text):
  r=subprocess.run(['awk','-v','checked=1234',AWK],input=text,text=True,capture_output=True,check=True)
  return json.loads(r.stdout)
 def test_valid_header_and_partial_expiry(self):
  q=self.parse('HTTP/2 200\nSubscription-Userinfo: upload=100; download=200; total=1000; expire=1700000000\n')
  self.assertEqual(q['state'],'ok');self.assertEqual(q['total'],1000);self.assertEqual(q['checked'],1234)
  self.assertEqual(self.parse('HTTP/2 200\nsubscription-userinfo: expire=1700000000\n')['state'],'ok')
 def test_redirect_headers_never_supply_quota_for_final_provider(self):
  q=self.parse('HTTP/1.1 302 Found\nsubscription-userinfo: total=1000\n\nHTTP/2 200\nOther: x\n')
  self.assertEqual(q['state'],'unavailable');self.assertNotIn('total',q)
 def test_untrusted_numeric_and_duplicate_values_rejected(self):
  for value in ['upload=-1; total=100','total=100; total=200','total=9007199254740992','upload=nan','total=1e9','total=100=200']:
   self.assertEqual(self.parse('HTTP/2 200\nsubscription-userinfo: '+value+'\n')['state'],'unavailable')
 def test_http_auth_error_and_missing_headers_are_distinct(self):
  self.assertEqual(self.parse('HTTP/2 401\nsubscription-userinfo: total=100\n')['state'],'request_failed')
  self.assertEqual(self.parse('HTTP/2 200\n')['state'],'unavailable')
 def test_header_only_cache_budget_and_source_invalidation(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c=d/'config';r=d/'ram';b=d/'bin';(c/'configs').mkdir(parents=True);r.mkdir();b.mkdir()
   (c/'configs/subscription').write_text('https://provider.example/private-token')
   (c/'configs/subscription-state.json').write_text('{"ua_b64":"Q2xhc2g=","applied_at":1}')
   (c/'configs/memory.json').write_text('{"protect_mb":14}')
   mem=d/'mem';mem.write_text('MemAvailable: 25000 kB\n')
   (b/'pidof').write_text('#!/bin/sh\nexit 0\n');(b/'pidof').chmod(0o700)
   (b/'curl').write_text('#!/bin/sh\necho called >> "'+str(d/'called')+'"\nprintf "HTTP/2 200\\nsubscription-userinfo: upload=10;download=20;total=100\\n"\n');(b/'curl').chmod(0o700)
   script=d/'quota.sh';script.write_text(SOURCE.replace('/data/ShellCrash',str(c)).replace('/tmp/ShellCrash',str(r)).replace('/proc/meminfo',str(mem)))
   env=dict(os.environ,PATH=str(b)+':'+os.environ['PATH'])
   def run(action):return json.loads(subprocess.check_output(['sh',str(script),'ax5',action],env=env,text=True))
   self.assertEqual(run('read')['state'],'unknown');self.assertFalse((d/'called').exists())
   self.assertEqual(run('check')['total'],100);self.assertEqual(run('read')['total'],100)
   (c/'configs/subscription').write_text('https://different.example/token');self.assertEqual(run('read')['state'],'unknown')
   mem.write_text('MemAvailable: 14000 kB\n');self.assertEqual(run('check')['state'],'memory')
   self.assertEqual((d/'called').read_text().count('called'),1)
   self.assertNotIn('private-token',(r/'subscription-quota.json').read_text())
