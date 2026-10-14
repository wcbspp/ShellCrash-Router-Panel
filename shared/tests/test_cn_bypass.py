"""Owned bypass ordering, rollback and operation isolation."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class CNBypass(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.p=Path(self.t.name);self.c=self.p/'C';self.d=self.p/'D';(self.c/'configs').mkdir(parents=True);self.d.mkdir();self.bin=self.p/'bin';self.bin.mkdir();self.state=self.p/'fw.json'
  self.chains={'nat:n':['-d 127.0.0.0/8 -j RETURN','-p udp --dport 53 -j REDIRECT','-p tcp -j REDIRECT'],'mangle:m':['-m mark --mark 1 -j RETURN','-p udp -j MARK']};self.state.write_text(json.dumps(self.chains))
  (self.bin/'iptables').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['FW']);d=json.loads(p.read_text());a=sys.argv[1:];op=a[2];k=a[1]+':'+a[3]
if k not in d:sys.exit(1)
if op=='-S':print('\\n'.join('-A '+a[3]+' '+r for r in d[k]));sys.exit(0)
if op=='-D':
 r=' '.join(a[4:])
 if r not in d[k]:sys.exit(1)
 d[k].remove(r)
elif op=='-I':
 if os.environ.get('FAIL_CHAIN')==a[3]:sys.exit(1)
 d[k].insert(int(a[4])-1,' '.join(a[5:]))
p.write_text(json.dumps(d))
''');(self.bin/'iptables').chmod(0o755)
  self.lib=ROOT/('ax5/cn-bypass-lib.sh'if(ROOT/'ax5').exists()else'payload/starts/cn-bypass-lib.sh')
  if not self.lib.exists():self.lib=ROOT.parent/'lib/cn-bypass.sh'
  self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'FW':str(self.state),'C':str(self.c),'D':str(self.d)}
 def tearDown(self):self.t.cleanup()
 def apply(self,mode='rule',safe='ready',prepared=True,fail=''):
  code=f'. "{self.lib}"; CB_NAT=n;CB_MANGLE=m;CB_SET=cn_ip;cb_safe(){{ echo {safe}; }};cb_prepare(){{ {"true"if prepared else"false"}; }};cb_rules {mode}'
  return subprocess.run(['sh','-c',code],env={**self.env,'FAIL_CHAIN':fail},capture_output=True,text=True)
 def enable(self):(self.c/'configs/cn-bypass').write_text('1\n')
 def result(self):return json.loads((self.d/'cn-state.json').read_text())
 def owned(self):return [r for rows in json.loads(self.state.read_text()).values()for r in rows if'SC_PANEL_CN_BYPASS'in r]
 def test_private_dns_guards_and_idempotence(self):
  self.enable();self.assertEqual(self.apply().returncode,0);self.assertTrue(self.result()['active']);d=json.loads(self.state.read_text());self.assertIn('SC_PANEL_CN_BYPASS',d['nat:n'][2]);self.assertIn('SC_PANEL_CN_BYPASS',d['mangle:m'][1]);self.assertEqual(d['nat:n'][:2],self.chains['nat:n'][:2]);self.apply();self.assertEqual(len(self.owned()),2)
 def test_nonrule_modes_remove_only_owned_rules(self):
  self.enable()
  for mode in ['global','direct','unknown']:
   self.apply();self.assertEqual(self.apply(mode).returncode,0);self.assertFalse(self.result()['active']);self.assertEqual(json.loads(self.state.read_text()),self.chains)
 def test_conflict_or_failed_table_leaves_core_routing(self):
  self.enable()
  for safe in ['invalid','fakeip']:
   self.apply();self.apply(safe=safe);self.assertFalse(self.result()['active']);self.assertFalse(self.owned());self.assertEqual(self.result()['reason'],safe)
  self.apply(prepared=False);self.assertEqual(self.result()['reason'],'unavailable');self.assertFalse(self.owned())
 def test_partial_failure_removes_all_owned_rules(self):
  self.enable();self.assertNotEqual(self.apply(fail='m').returncode,0);self.assertFalse(self.owned());self.assertFalse(self.result()['active']);self.assertEqual(json.loads(self.state.read_text()),self.chains)
 def test_disable_restores_original_chains(self):
  self.enable();self.apply();(self.c/'configs/cn-bypass').write_text('0\n');self.apply();self.assertFalse(self.result()['enabled']);self.assertEqual(json.loads(self.state.read_text()),self.chains)
 def test_table_prepare_is_bounded_and_reuses_validated_set(self):
  validator=ROOT/('ax5/rules_validate.awk'if(ROOT/'ax5').exists()else'payload/starts/rules_validate.awk')
  if not validator.exists():validator=ROOT.parent/'lib/rules_validate.awk'
  mem=self.p/'mem';mem.write_text('MemAvailable: 17000 kB\n');helper=self.p/'bounded';helper.write_text(self.lib.read_text().replace('/proc/meminfo',str(mem)))
  table=self.c/'configs/cn_ip.txt';table.write_bytes((ROOT/'examples/cn_ip.default.txt').read_bytes())
  executable=self.bin/'ipset';executable.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$D/ipset.log"\n[ "$1" != list ] || [ -f "$D/set-created" ] || exit 1\n[ "$1" != swap ] || touch "$D/set-created"\nexit 0\n');executable.chmod(0o755)
  code=f'. "{helper}";CB_SET=cn_ip;CB_PROTECT=12;CB_VALIDATOR="{validator}";cb_prepare'
  def prepare():return subprocess.run(['sh','-c',code],env=self.env,capture_output=True,text=True).returncode
  self.assertEqual(prepare(),0);before=(self.d/'ipset.log').read_text();self.assertIn('swap sc_cn_stage cn_ip',before);self.assertFalse((self.d/'cn-valid').exists());self.assertEqual(prepare(),0);self.assertEqual((self.d/'ipset.log').read_text().count('swap'),1)
  table.write_text('8.152.1.1/13\n');self.assertNotEqual(prepare(),0);self.assertEqual((self.d/'ipset.log').read_text().count('swap'),1)
  table.write_text('8.152.0.0/13\n');mem.write_text('MemAvailable: 13000 kB\n');self.assertNotEqual(prepare(),0);self.assertFalse((self.d/'cn-valid').exists());self.assertFalse((self.d/'cn-restore').exists())
 def test_live_lock_rejects_concurrent_mutation(self):
  self.enable();(self.d/'cn-rule.lock').mkdir();(self.d/'cn-rule.lock/owner').write_text(str(os.getpid()));self.assertNotEqual(self.apply().returncode,0);self.assertEqual(json.loads(self.state.read_text()),self.chains)
if __name__=='__main__':unittest.main()
