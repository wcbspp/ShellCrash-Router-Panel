"""Imported proxy/reject rules block firewall bypass; routing defaults do not."""
import json,subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class Check(unittest.TestCase):
 def check(self,rules,out=None,priority=0):
  obj={'outbounds':out or[{'type':'direct','tag':'direct'}],'route':{'final':'proxy-main','rules':rules}}
  raw='{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,separators=(',',':'),ensure_ascii=False)for k,v in obj.items())+'\n}'
  return subprocess.run(['awk','-v','priority='+str(priority),'-f',str(ROOT/'payload/starts/cn_bypass_check.awk')],input=raw,text=True,capture_output=True).returncode
 def test_direct_dns_mode_guards_and_final_proxy_allowed(self):
  self.assertEqual(self.check([{'clash_mode':'Global','outbound':'proxy-main'},{'action':'sniff'},{'protocol':'dns','action':'hijack-dns'},{'rule_set':['geoip-cn'],'outbound':'direct'},{'outbound':'proxy-main','action':'route'}]),0)
 def test_proxy_reject_nested_and_conditional_mode_rules_blocked(self):
  for rule in [{'domain_suffix':['example.com'],'outbound':'proxy-main'},{'action':'reject'},{'type':'logical','rules':[{'outbound':'direct'}],'outbound':'proxy-main'},{'rules':[{'outbound':'proxy-main'}],'outbound':'direct'},{'clash_mode':'Rule','outbound':'proxy-main'},{'clash_mode':'Global','domain':['example.com'],'outbound':'proxy-main'},{'outbound':'direct','action':'reject'}]:
   with self.subTest(rule=rule):
    self.assertNotEqual(self.check([rule]),0,'conditional proxy rules require a priority warning');self.assertEqual(self.check([rule],priority=1),0,'explicit domestic-IP priority remains available')
 def test_wrong_direct_tag_cannot_be_bypassed(self):self.assertNotEqual(self.check([],[{'type':'selector','tag':'direct','outbounds':['node']}],priority=1),0)
