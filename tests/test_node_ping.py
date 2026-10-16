import json,os,subprocess,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def key(name):
 h=0
 for b in name.encode():h=(h*131+b)%2147483647
 return str(h)
class PingTarget(unittest.TestCase):
 def parse(self,nodes,name='node',ascii=False):
  raw='"outbounds":'+json.dumps(nodes,ensure_ascii=ascii,separators=(',',':'))+',\n'
  return subprocess.run(['awk','-f',str(ROOT/'shared/lib/node-ping-target.awk')],input=raw.encode(),env={**os.environ,'LC_ALL':'C','NODE_PING_KEY':key(name)},capture_output=True)
 def test_exact_unicode_and_escaped_names(self):
  for name in ['node','台湾 🇹🇼','literal\\path','quote"node']:
   for ascii in [False,True]:
    r=self.parse([{'tag':name,'server':'example.com','tls':{'server':'wrong.example'}}],name,ascii);self.assertEqual((r.returncode,r.stdout),(0,b'example.com\n'))
 def test_ambiguous_chained_missing_and_injected_hosts(self):
  cases=[[{'tag':'node','server':'a.example'}]*2,[{'tag':'node','server':'a.example','detour':'other'}],[{'tag':'node','type':'selector'}],[{'tag':'node','server':'-Ifoo'}],[{'tag':'node','server':'a;touch x'}],[{'tag':'node','server':'::1'}]]
  for nodes in cases:
   r=self.parse(nodes);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,b'')
 def test_bounded_and_malformed_input(self):
  for raw in [b'"outbounds":[{"tag":"node","server":"a","server":"b"}],\n',b'"outbounds":[{bad}],\n',b'"outbounds":['+b' '*262144+b']\n']:
   r=subprocess.run(['awk','-f',str(ROOT/'shared/lib/node-ping-target.awk')],input=raw,env={**os.environ,'NODE_PING_KEY':key('node'),'LC_ALL':'C'},capture_output=True);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,b'')
class PingWorker(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name);self.C=self.base/'C';self.D=self.base/'D';self.bin=self.base/'bin';self.bin.mkdir();(self.C/'starts').mkdir(parents=True);(self.C/'jsons').mkdir();self.D.mkdir();(self.C/'starts/node-ping-target.awk').write_bytes((ROOT/'shared/lib/node-ping-target.awk').read_bytes());self.config=self.C/'jsons/config.json';self.config.write_text('"outbounds":[{"tag":"node","server":"example.com"}],\n');self.resource();self.shim('pidof','echo 1');self.shim('ping','echo called >> "$D/calls";echo "64 bytes: time=67.500 ms"');self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'C':str(self.C),'D':str(self.D)}
 def shim(self,name,body):
  p=self.bin/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o700)
 def resource(self,avail=65536): (self.C/'starts/resource_health.sh').write_text('resource_read(){ rh_available='+str(avail)+';rh_protect_mb=12; }\n')
 def run_worker(self,nonce='1234abcd'):
  return subprocess.run(['sh',str(ROOT/'shared/lib/node-ping.sh'),'k2p',nonce,key('node')],env=self.env,capture_output=True,timeout=8)
 def result(self):return json.loads((self.D/'nodepingresult.json').read_text())
 def test_single_ping_bound_to_native_config_and_cleanup(self):
  before=self.config.read_bytes();self.assertEqual(self.run_worker().returncode,0);r=self.result();self.assertEqual((r['state'],r['delay']),('done',67.5));self.assertEqual((self.D/'calls').read_text(),'called\n');self.assertEqual(before,self.config.read_bytes());self.assertFalse((self.D/'node-ping.lock').exists())
 def test_low_memory_and_operation_rejected_before_ping(self):
  self.resource(12000);self.run_worker();self.assertEqual(self.result()['state'],'low_memory');self.assertFalse((self.D/'calls').exists());self.resource();(self.D/'operation.lock').mkdir();self.run_worker();self.assertEqual(self.result()['state'],'busy');self.assertFalse((self.D/'calls').exists())
 def test_failure_is_no_icmp_response_and_changed_config_invalidates(self):
  self.shim('ping','exit 1');self.run_worker();self.assertEqual(self.result()['state'],'no_reply');self.shim('ping','echo " " >> "$C/jsons/config.json";echo "time=12 ms"');self.run_worker();self.assertEqual(self.result()['state'],'changed')
 def test_deadline_without_timeout_dependency(self):
  self.shim('ping','exec sleep 10');start=time.monotonic();self.run_worker();self.assertLess(time.monotonic()-start,6);self.assertEqual(self.result()['state'],'no_reply');self.assertFalse((self.D/'node-ping.lock').exists())
 def test_small_ram_index_reused_and_changed_config_rebuilds(self):
  self.run_worker();self.assertEqual(self.result()['state'],'done');index=self.D/'node-ping-index.tsv';self.assertLess(index.stat().st_size,65536);before=index.read_bytes();(self.C/'starts/node-ping-target.awk').write_text('BEGIN{exit 1}\n');self.run_worker();self.assertEqual(self.result()['state'],'done');self.assertEqual(index.read_bytes(),before);self.config.write_text(self.config.read_text()+' ');self.run_worker();self.assertEqual(self.result()['state'],'unsupported')
 def test_lock_rejects_second_worker(self):
  (self.D/'node-ping.lock').mkdir();self.assertNotEqual(self.run_worker().returncode,0);self.assertFalse((self.D/'calls').exists())
class AXTarget(unittest.TestCase):
 def test_exact_stream_parser_both_core_profiles_and_detour_refusal(self):
  from lupa import LuaRuntime
  for kind in ['singbox','meta']:
   for detour in ['', 'other']:
    with tempfile.TemporaryDirectory() as t:
     c=Path(t);(c/'ax5').mkdir();(c/'configs').mkdir();(c/'ax5/inspect.lua').write_bytes((ROOT/'profiles/ax5/ax5/inspect.lua').read_bytes());(c/'configs/config.json').write_text(json.dumps({'nested':{'outbounds':[{'tag':'台湾 🇹🇼','server':'wrong.example'}]},'padding':'x'*20000,'outbounds':[{'tag':'台湾 🇹🇼','server':'example.com','detour':detour}],'_native_meta':{} if kind=='meta' else None},ensure_ascii=False))
     lua=LuaRuntime(unpack_returned_tuples=True);M=lua.table_from({'C':str(c),'json':lua.table_from({'decode':lambda s:lua.table_from(json.loads(s),recursive=True)})});lua.globals().M=M;lua.globals().arg=lua.table_from({1:key('台湾 🇹🇼')});out=[];lua.globals().capture=lambda *args:out.append(''.join(args));lua.execute("local real=dofile;dofile=function(p)if p=='/data/ShellCrash/ax5/common.lua'then return M end;return real(p)end;io.write=capture;os.exit=function()error('refused')end")
     source=(ROOT/'profiles/ax5/ax5/node-ping-target.lua').read_text()
     if detour:
      with self.assertRaises(Exception):lua.execute(source)
     else:lua.execute(source);self.assertEqual(''.join(out),'example.com\n')
