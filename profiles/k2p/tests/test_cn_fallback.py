"""Domestic fallback uses the current ShellCrash table, after explicit routing."""
import ipaddress,json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'payload/starts'
class CNFallback(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name);self.c=self.p/'C';self.w=self.p/'work'
  (self.c/'starts').mkdir(parents=True);(self.c/'configs').mkdir();self.w.mkdir()
  validator=SOURCE/'rules_validate.awk'
  if not validator.exists():validator=ROOT.parents[1]/'shared/lib/rules_validate.awk'
  for name in ['cn_fallback.awk','resource_health.sh']:(self.c/'starts'/name).write_bytes((SOURCE/name).read_bytes())
  (self.c/'starts/rules_validate.awk').write_bytes(validator.read_bytes())
  self.table=(ROOT/'examples/cn_ip.default.txt').read_bytes();(self.c/'configs/cn_ip.txt').write_bytes(self.table)
  self.mem=self.p/'meminfo';self.mem.write_text('MemAvailable: 20000 kB\n')
  self.helper=self.p/'helper';self.helper.write_text((SOURCE/'cn_fallback.sh').read_text().replace('/proc/meminfo',str(self.mem)))
  self.env={**os.environ,'C':str(self.c),'CRASHDIR':str(self.c),'SC_CN_WORK':str(self.w)}
  self.config={'dns':{'fixture':'local'},'outbounds':[{'type':'direct','tag':'direct'},{'type':'selector','tag':'proxy-main','outbounds':['node']},{'type':'anytls','tag':'node','server':'fixture.test','server_port':443,'password':'fixture'}], 'route':{'rules':[{'clash_mode':'Global','outbound':'proxy-main'},{'domain_suffix':['cn.fixture'],'outbound':'node'},{'rule_set':['geoip-cn'],'outbound':'direct'}],'final':'proxy-main','rule_set':[{'type':'inline','tag':'geoip-cn','rules':[{'ip_cidr':['223.5.5.0/24']}]}]}}
 def tearDown(self):self.tmp.cleanup()
 def run_prepare(self,obj=None):
  obj=obj or self.config;self.infile=self.p/'input';self.out=self.p/'output'
  self.infile.write_text('{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,separators=(',',':'),ensure_ascii=False) for k,v in obj.items())+'\n}\n')
  return subprocess.run(['sh','-c','. "'+str(self.helper)+'"; cn_fallback_prepare "'+str(self.infile)+'" "'+str(self.out)+'"'],env=self.env,capture_output=True,text=True,timeout=10)
 def result(self):return json.loads(self.out.read_text())
 def test_current_domestic_table_covers_gap_and_keeps_explicit_rule_order(self):
  self.assertEqual(self.run_prepare().returncode,0)
  o=self.result();self.assertEqual(o['dns'],self.config['dns']);self.assertEqual(o['outbounds'],self.config['outbounds'])
  self.assertEqual(o['route']['rules'][:-1],self.config['route']['rules']);self.assertEqual(o['route']['final'],'proxy-main')
  f=o['route']['rules'][-1];self.assertEqual(f,{'rule_set':['panel-cn-ip'],'outbound':'direct'})
  rows=json.loads((self.w/'cn-ip.json').read_text())['rules'][0]['ip_cidr'];target=ipaddress.ip_address('8.153.13.81')
  self.assertTrue(any(target in ipaddress.ip_network(n) for n in rows));self.assertFalse(any(ipaddress.ip_address('8.8.8.8') in ipaddress.ip_network(n) for n in rows))
 def test_fallback_precedes_only_default_match_and_is_idempotent(self):
  terminal={'action':'route','outbound':'proxy-main'};self.config['route']['rules'].append(terminal)
  self.assertEqual(self.run_prepare().returncode,0);o=self.result();self.assertEqual(o['route']['rules'][-1],terminal);self.assertEqual(o['route']['rules'][-2]['rule_set'],['panel-cn-ip'])
  self.assertEqual(self.run_prepare(o).returncode,0);self.assertEqual(self.result(),o)
 def test_rule_set_first_field_and_nested_strings_do_not_confuse_scanner(self):
  r=self.config['route'];self.config['route']={'rule_set':r['rule_set'],'final':r['final'],'rules':r['rules']}
  self.config['outbounds'][1]['tag']='proxy-main 字符串 { [ \\"rules\\"';self.config['outbounds'][0]['extra']='fixture'
  self.assertEqual(self.run_prepare().returncode,0);self.assertEqual(len(self.result()['route']['rule_set']),2)
 def test_no_resource_array_adds_one_without_changing_final(self):
  del self.config['route']['rule_set'];self.config['route']['rules']=[]
  self.assertEqual(self.run_prepare().returncode,0);self.assertEqual(len(self.result()['route']['rule_set']),1);self.assertEqual(self.result()['route']['final'],'proxy-main')
 def test_invalid_table_settings_and_reserved_collision_preserve_previous_files(self):
  self.assertEqual(self.run_prepare().returncode,0);before=self.out.read_bytes();asset=(self.w/'cn-ip.json').read_bytes()
  (self.c/'configs/cn_ip.txt').write_bytes(self.table+b'8.153.13.81/13\n');self.assertNotEqual(self.run_prepare().returncode,0)
  (self.c/'configs/cn_ip.txt').write_bytes(self.table);(self.c/'configs/memory.conf').write_text('warning_mb=24\nprotect_mb=20\ncleanup_mb=0\n');self.assertNotEqual(self.run_prepare().returncode,0)
  (self.c/'configs/memory.conf').unlink();self.config['route']['rule_set'].append({'type':'inline','tag':'panel-cn-ip','rules':[]});self.assertNotEqual(self.run_prepare().returncode,0)
  self.assertEqual(self.out.read_bytes(),before);self.assertEqual((self.w/'cn-ip.json').read_bytes(),asset)
