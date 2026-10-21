"""Policy validation and transactional firewall semantics; no device claim."""
import json, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'shared/lib/proxy-access.sh'
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['ACL_FW']);d=json.loads(p.read_text());a=sys.argv[1:];t='filter'
if a[:1]==['-t']:t=a[1];a=a[2:]
if 'ip6tables' in sys.argv[0]:t='6'+t
op=a[0];c=a[1] if len(a)>1 else '';key=t+':'+c
if op=='-S':
 if c and key not in d:sys.exit(1)
 for k,rows in d.items():
  table,chain=k.split(':')
  if table==t and (not c or c==chain):
   for r in rows:print('-A '+chain+' '+' '.join(r))
 sys.exit(0)
if op=='-N':
 if key in d:sys.exit(1)
 d[key]=[]
elif key not in d:sys.exit(1)
elif op=='-A':
 if os.environ.get('ACL_FAIL')=='mac' and '--mac-source' in a:sys.exit(1)
 d[key].append(a[2:])
elif op=='-I':
 n=int(a[2]) if a[2].isdigit() else 1;rule=a[3:] if a[2].isdigit() else a[2:]
 if os.environ.get('ACL_FAIL')=='mangle' and t=='mangle':sys.exit(1)
 d[key].insert(n-1,rule)
elif op=='-D':
 if a[2:] not in d[key]:sys.exit(1)
 d[key].remove(a[2:])
elif op=='-F':d[key]=[]
elif op=='-X':
 if d[key] or any(r[-2:]==['-j',c] for k,rows in d.items() if k.split(':')[0]==t for r in rows):sys.exit(1)
 del d[key]
else:sys.exit(2)
p.write_text(json.dumps(d))
'''
class ProxyAccess(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.p=Path(self.tmp.name)
  self.c=self.p/'C';(self.c/'configs').mkdir(parents=True);self.bin=self.p/'bin';self.bin.mkdir();self.fw=self.p/'fw'
  self.base={'filter:INPUT':[['-j','ACCEPT']], 'filter:FORWARD':[['-j','ACCEPT']], 'nat:SC_AX5_IN':[['-j','REDIRECT']], 'nat:SC_AX5_LDNS':[['-j','REDIRECT']], 'mangle:SC_AX5_UDP':[['-j','MARK']]}
  self.base.update({'6filter:INPUT':[['-j','ACCEPT']],'6filter:FORWARD':[['-j','ACCEPT']]})
  self.fw.write_text(json.dumps(self.base))
  (self.bin/'iptables').write_text(FAKE);(self.bin/'iptables').chmod(0o700)
  # Reuse one simulated family; applying it twice also checks duplicate cleanup.
  (self.bin/'ip6tables').symlink_to(self.bin/'iptables')
  self.env=dict(os.environ,PATH=str(self.bin)+':'+os.environ['PATH'],C=str(self.c),SC_ACCESS_RUNTIME=str(self.p/'run'),ACL_FW=str(self.fw))
 def runsh(self,cmd,**env):
  return subprocess.run(['sh','-c','. "$1"; '+cmd,'sh',str(SCRIPT)],env=dict(self.env,**env),text=True,capture_output=True)
 def policy(self,text):
  p=self.c/'configs/proxy-access';p.write_text(text);return p
 def enabled(self):
  self.policy('1\n02:11:22:33:44:55\n');self.assertEqual(self.runsh('ac_apply').returncode,0)
 def test_validation_and_empty_enabled(self):
  for text in ['1\n','0\n02:11:22:33:44:55\n','1\nAA:00:11:22:33:44\n']:
   self.policy(text);self.assertEqual(self.runsh('ac_validate "$C/configs/proxy-access"').returncode,0,text)
  for text in ['', 'yes\n','1\nff:ff:ff:ff:ff:ff\n','1\n00:00:00:00:00:00\n','1\n02:11:22:33:44:55;id\n','1\n02:11:22:33:44:55\n02:11:22:33:44:55\n']:
   self.policy(text);self.assertNotEqual(self.runsh('ac_validate "$C/configs/proxy-access"').returncode,0,text)
 def test_default_disabled_leaves_original_firewall(self):
  self.assertEqual(self.runsh('ac_apply').returncode,0);self.assertEqual(json.loads(self.fw.read_text()),self.base)
 def test_whitelist_covers_dns_redir_udp_and_explicit_existing_connections(self):
  self.enabled();d=json.loads(self.fw.read_text())
  for parent in ['nat:SC_AX5_IN','nat:SC_AX5_LDNS','mangle:SC_AX5_UDP']:
   gate=parent.split(':')[0]+':'+d[parent][0][-1]
   self.assertEqual(d[gate][-1],['-j','ACCEPT'])
   self.assertIn(['-m','mac','--mac-source','02:11:22:33:44:55','-j','RETURN'],d[gate])
  # Reject hook precedes every pre-existing INPUT rule (including ACCEPT).
  for rule in d['filter:INPUT'][:2]:
   self.assertIn('--dports',rule);self.assertIn('7890,7892,7893,1053',rule)
   self.assertEqual(d['filter:'+rule[-1]][-1],['-j','REJECT'])
  self.assertEqual(d['filter:FORWARD'][0][0:2],['-o','utun'])
 def test_replace_failure_keeps_previous_complete_policy(self):
  self.enabled();before=json.loads(self.fw.read_text())
  self.assertNotEqual(self.runsh('ac_apply',ACL_FAIL='mangle').returncode,0)
  self.assertEqual(json.loads(self.fw.read_text()),before)
 def test_disable_removes_all_owned_rules_and_retains_saved_macs(self):
  self.enabled();self.policy('0\n02:11:22:33:44:55\n');self.assertEqual(self.runsh('ac_apply').returncode,0)
  self.assertEqual(json.loads(self.fw.read_text()),self.base)
  self.assertIn('02:11', (self.c/'configs/proxy-access').read_text())
 def test_persistence_failure_restores_original_policy(self):
  self.enabled();candidate=self.p/'candidate';candidate.write_text('1\n02:22:33:44:55:66\n')
  self.env['CANDIDATE']=str(candidate)
  result=self.runsh('save_safe(){ return 1; };ac_commit "$CANDIDATE"')
  self.assertNotEqual(result.returncode,0)
  self.assertEqual((self.c/'configs/proxy-access').read_text(),'1\n02:11:22:33:44:55\n')
  d=json.loads(self.fw.read_text());self.assertNotIn('02:22:33:44:55:66',json.dumps(d))
 def test_empty_list_rejects_all_and_missing_mac_support_does_not_open_saved_policy(self):
  self.policy('1\n');self.assertEqual(self.runsh('ac_apply').returncode,0)
  d=json.loads(self.fw.read_text());self.assertEqual(d['filter:SC_ACL_A_I'],[['-i','lo','-j','RETURN'],['-j','REJECT']])
  self.policy('1\n02:11:22:33:44:55\n')
  self.assertNotEqual(self.runsh('ac_enforce',ACL_FAIL='mac').returncode,0)
  d=json.loads(self.fw.read_text());self.assertEqual(d['filter:INPUT'][0][-1],'SC_ACL_LOCK')
  self.assertEqual(d['filter:SC_ACL_LOCK'][-1],['-j','REJECT'])
if __name__=='__main__':unittest.main()
