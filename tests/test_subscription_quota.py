import json, os, subprocess, tempfile, unittest, re, time
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

 def test_auto_events_coalesce_defer_and_run_again_for_new_core(self):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);c=d/'config';r=d/'ram';b=d/'bin';(c/'configs').mkdir(parents=True);r.mkdir();b.mkdir()
   (c/'configs/subscription').write_text('https://provider.example/private-token')
   state=c/'configs/subscription-state.json';state.write_text('{"ua_b64":"Q2xhc2g=","applied_at":1}')
   (c/'configs/memory.json').write_text('{"protect_mb":14}')
   mem=d/'mem';mem.write_text('MemAvailable: 25000 kB\n');epoch=d/'epoch';epoch.write_text('core1')
   (b/'pidof').write_text('#!/bin/sh\necho 1\n');(b/'pidof').chmod(0o700)
   curl=b/'curl';curl.write_text('#!/bin/sh\necho called >> "'+str(d/'called')+'"\nprintf "HTTP/2 200\\nsubscription-userinfo: upload=10;download=20;total=100\\n"\n');curl.chmod(0o700)
   (b/'sleep').write_text('#!/bin/sh\n/bin/sleep 0.05\n');(b/'sleep').chmod(0o700)
   script=d/'quota.sh';text=SOURCE.replace('/data/ShellCrash',str(c)).replace('/tmp/ShellCrash',str(r)).replace('/proc/meminfo',str(mem))
   text=re.sub(r'core_epoch\(\)\{.*?\n\}', 'core_epoch(){ cat "'+str(epoch)+'"; }',text,count=1,flags=re.S);script.write_text(text)
   env=dict(os.environ,PATH=str(b)+':'+os.environ['PATH'])
   def run(action):return subprocess.check_output(['sh',str(script),'ax5',action],env=env,text=True)
   def finished():
    deadline=time.time()+6
    while (r/'quota-auto.lock').exists()and time.time()<deadline:time.sleep(.03)
    self.assertFalse((r/'quota-auto.lock').exists())
   (r/'operation.lock').touch();run('auto');time.sleep(.1);self.assertFalse((d/'called').exists())
   state.write_text('{"ua_b64":"Q2xhc2g=","applied_at":2}');run('auto');run('auto');(r/'operation.lock').unlink();finished()
   self.assertEqual((d/'called').read_text().count('called'),1)
   run('auto');time.sleep(.1);self.assertEqual((d/'called').read_text().count('called'),1)
   epoch.write_text('core2');run('auto');finished();self.assertEqual((d/'called').read_text().count('called'),2)
   self.assertEqual(json.loads(run('read'))['total'],100)
   curl.write_text('#!/bin/sh\nprintf "HTTP/2 503\\n"\n');out=json.loads(run('check'));self.assertEqual(out['state'],'ok');self.assertEqual(out['total'],100);self.assertEqual(out['attempt_state'],'request_failed')
   state.write_text('{"ua_b64":"Q2xhc2g=","applied_at":3}');self.assertEqual(json.loads(run('check'))['state'],'request_failed')
 def test_hooks_only_schedule_after_success(self):
  ax=(ROOT/'profiles/ax5/ax5/job.lua').read_text();self.assertIn("if ok and(req.action=='apply'",ax)
  ready=(ROOT/'profiles/ax5/ax5/run.sh').read_text();self.assertLess(ready.index('service-ready"\n   sh'),ready.index('subscription-quota.sh'))
  k=(ROOT/'profiles/k2p/payload/starts/manage.sh').read_text();self.assertIn('phase done subscription_updated;',k);self.assertIn('subscription-quota.sh" k2p auto',k[k.index('phase done subscription_updated;'):])
  hook=(ROOT/'profiles/k2p/payload/starts/panel_afstart.sh').read_text();self.assertLess(hook.index('subscription-quota.sh'),hook.index('[ "$transport" !='))
