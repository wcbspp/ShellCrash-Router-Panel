import json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MOCK=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['MOCK_STATE']);d=json.loads(p.read_text());a=sys.argv[1:];tool=Path(sys.argv[0]).name
if tool=='curl':
 if '-d' in a:d['mode']=json.loads(a[a.index('-d')+1])['mode']
 else:print(json.dumps({'mode':d['mode']}))
elif tool=='pidof':sys.exit(1)
elif tool=='iptables-restore':
 f=Path(os.environ['MOCK_FAIL'])
 if f.exists():f.unlink();sys.exit(1)
 for line in sys.stdin.read().splitlines():
  x=line.split()
  if x and x[0].startswith(':'):d['chains'][x[0][1:]]=[]
  if x and x[0]=='-A':d['chains'][x[1]].append(line)
elif tool=='iptables':
 a=a[2:] if a[:1]==['-t'] else a
 op,chain=a[:2]
 if chain not in d['chains']:sys.exit(1)
 if op=='-S':print('-N '+chain);print('\n'.join(d['chains'][chain]));sys.exit(0)
 if op=='-I':d['chains'][chain].insert(0,'-A '+chain+' '+' '.join(a[3:]))
 if op=='-D':
  row='-A '+chain+' '+' '.join(a[2:])
  if row not in d['chains'][chain]:sys.exit(1)
  d['chains'][chain].remove(row)
p.write_text(json.dumps(d))
'''
class TrafficMode(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name);b=self.p/'bin';b.mkdir()
  for name in ['curl','pidof','iptables','iptables-restore']:
   f=b/name;f.write_text(MOCK);f.chmod(0o755)
  starts=self.p/'starts';starts.mkdir();(starts/'policy_capture.sh').write_bytes((ROOT/'payload/starts/policy_capture.sh').read_bytes())
  self.config=self.p/'configs';self.config.mkdir();(self.config/'ShellCrash.cfg').write_text('secret=fixture\n')
  self.state=self.p/'state.json';self.original={'PREROUTING':[],'shellcrash':['-A shellcrash -d 192.168.0.0/16 -j RETURN','-A shellcrash -m set --match-set cn_ip dst -j RETURN','-A shellcrash -s 192.168.1.0/24 -p tcp -j REDIRECT --to-ports 7892'],'shellcrash_dns':['-A shellcrash_dns -p udp -j REDIRECT --to-ports 1053']}
  self.state.write_text(json.dumps({'mode':'rule','chains':self.original}))
  self.env={**os.environ,'PATH':str(b)+':'+os.environ['PATH'],'MOCK_STATE':str(self.state),'MOCK_FAIL':str(self.p/'fail'),'SC_TRAFFIC_ROOT':str(self.p/'traffic'),'SC_TRAFFIC_MODE_FILE':str(self.p/'mode')}
 def tearDown(self):self.tmp.cleanup()
 def run_mode(self,mode):
  script=f'C="{self.p}"; PANEL_LAN_IP=127.0.0.1; . "{ROOT}/payload/starts/traffic_mode.sh"; traffic_mode_apply {mode}'
  return subprocess.run(['sh','-c',script],env=self.env,capture_output=True,text=True)
 def data(self):return json.loads(self.state.read_text())
 def test_roundtrip_direct_global_rule(self):
  self.assertEqual(self.run_mode('direct').returncode,0);d=self.data();self.assertEqual(d['mode'],'direct')
  for c in ['shellcrash','shellcrash_dns']:self.assertIn('SC_PANEL_DIRECT',d['chains'][c][0]);self.assertTrue(d['chains'][c][0].endswith('-j RETURN'))
  self.assertEqual(self.run_mode('global').returncode,0);d=self.data();self.assertFalse(any('cn_ip' in r for r in d['chains']['shellcrash']));self.assertIn('SC_PANEL_GLOBAL',d['chains']['PREROUTING'][0]);self.assertIn('192.168.0.0/16',d['chains']['shellcrash'][0])
  self.assertEqual(self.run_mode('rule').returncode,0);self.assertEqual(self.data()['chains'],self.original);self.assertEqual(self.data()['mode'],'rule');self.assertFalse((self.p/'traffic/auth').exists())
 def test_native_template_rule_mode_reaches_core_for_country_ip(self):
  (self.config/'native-profile').write_text('singbox\n')
  self.assertEqual(self.run_mode('direct').returncode,0)
  self.assertEqual(self.run_mode('rule').returncode,0)
  self.assertFalse(any('cn_ip' in r for r in self.data()['chains']['shellcrash']))
  self.assertTrue(any('192.168.0.0/16' in r for r in self.data()['chains']['shellcrash']))
 def test_custom_domain_rules_reach_core_for_country_ip(self):
  (self.config/'policy.tsv').write_text('suffix\tfixture.example\tproxy-main\n')
  self.original['shellcrash_mark']=['-A shellcrash_mark -d 192.168.0.0/16 -j RETURN','-A shellcrash_mark -m set --match-set cn_ip dst -j RETURN','-A shellcrash_mark -p udp -j MARK --set-mark 7892']
  self.state.write_text(json.dumps({'mode':'rule','chains':self.original}))
  self.assertEqual(self.run_mode('global').returncode,0)
  self.assertEqual(self.run_mode('rule').returncode,0)
  for chain in ['shellcrash','shellcrash_mark']:
   self.assertFalse(any('cn_ip' in r for r in self.data()['chains'][chain]))
   self.assertTrue(any('192.168.0.0/16' in r for r in self.data()['chains'][chain]))
 def test_firewall_failure_restores_previous(self):
  (self.p/'fail').touch();self.assertNotEqual(self.run_mode('global').returncode,0);self.assertEqual(self.data(),{'mode':'rule','chains':self.original});self.assertFalse((self.p/'traffic/auth').exists())
 def test_invalid_mode_does_not_mutate(self):
  self.assertNotEqual(self.run_mode('invalid').returncode,0);self.assertEqual(self.data(),{'mode':'rule','chains':self.original})
 def test_mixed_udp_chains_roundtrip(self):
  self.original['shellcrash_mark']=['-A shellcrash_mark -d 192.168.0.0/16 -j RETURN','-A shellcrash_mark -m set --match-set cn_ip dst -j RETURN','-A shellcrash_mark -j MARK --set-mark 7892']
  self.state.write_text(json.dumps({'mode':'rule','chains':self.original}))
  self.assertEqual(self.run_mode('direct').returncode,0)
  self.assertIn('SC_PANEL_DIRECT',self.data()['chains']['shellcrash_mark'][0])
  self.assertEqual(self.run_mode('global').returncode,0)
  self.assertFalse(any('cn_ip' in r for r in self.data()['chains']['shellcrash_mark']))
  self.assertTrue(any('192.168.0.0/16' in r for r in self.data()['chains']['shellcrash_mark']))
  self.assertEqual(self.run_mode('rule').returncode,0);self.assertEqual(self.data()['chains'],self.original)
if __name__=='__main__':unittest.main()
