"""Actual chunked HTTP response exercises the shell cap, with no router state."""
import http.server,threading,tempfile,unittest,subprocess,os,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class TrafficSample(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.p=Path(self.t.name);self.body=b'{"uploadTotal":1024,"downloadTotal":2048,"connections":[]}';self.requests=0
  owner=self
  class Handler(http.server.BaseHTTPRequestHandler):
   def log_message(self,*args):pass
   def do_GET(self):
    owner.requests+=1;self.send_response(200);self.send_header('Transfer-Encoding','chunked');self.end_headers()
    try:
     for i in range(0,len(owner.body),4096):
      b=owner.body[i:i+4096];self.wfile.write(('%x\r\n'%len(b)).encode()+b+b'\r\n');self.wfile.flush()
     self.wfile.write(b'0\r\n\r\n')
    except (BrokenPipeError,ConnectionResetError):pass
  self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=self.server.serve_forever,daemon=True).start();self.addCleanup(self.server.server_close);self.addCleanup(self.server.shutdown)
  c=self.p/'C';(c/'configs').mkdir(parents=True);(c/'starts').mkdir();(c/'configs/ShellCrash.cfg').write_text('secret=fixture\n');(c/'starts/resource_health.sh').write_bytes((ROOT/'payload/starts/resource_health.sh').read_bytes())
  b=self.p/'bin';b.mkdir();f=b/'pidof';f.write_text('#!/bin/sh\necho 777\n');f.chmod(0o700)
  (self.p/'stat').write_text('777 (CrashCore) S '+'0 '*18+'12345\n');(self.p/'uptime').write_text('5.00 0.00\n')
  text=(ROOT/'payload/starts/traffic_sample.sh').read_text().replace('/tmp/sc-admin',str(self.p/'ram')).replace('/proc/meminfo',str(self.p/'meminfo')).replace('"/proc/$pid/stat"','"'+str(self.p/'stat')+'"').replace('/proc/uptime',str(self.p/'uptime')).replace('http://${PANEL_LAN_IP}:9999/connections','http://127.0.0.1:'+str(self.server.server_port)+'/connections')
  self.script=self.p/'sample.sh';self.script.write_text(text);self.env={**os.environ,'PATH':str(b)+os.pathsep+os.environ['PATH']}
 def sample(self,available=24000):
  (self.p/'meminfo').write_text('MemAvailable: %s kB\n'%available)
  r=subprocess.run(['sh','-c','C="$1";. "$2";traffic_sample','test',str(self.p/'C'),str(self.script)],capture_output=True,text=True,env=self.env,timeout=8);self.assertEqual(r.returncode,0,r.stderr);return json.loads(r.stdout)
 def test_valid_chunked_counters_and_cleanup(self):
  d=self.sample();self.assertEqual(d['upTotal'],1024);self.assertEqual(d['downTotal'],2048);self.assertEqual(d['epoch'],'777-12345');self.assertFalse(list((self.p/'ram').glob('traffic-*')))
 def test_oversized_chunked_response_is_rejected_and_deleted(self):
  self.body=b'{"uploadTotal":1,"downloadTotal":2,"padding":"'+b'x'*2097152+b'"}';self.assertEqual(self.sample()['error'],'traffic_unavailable');self.assertFalse(list((self.p/'ram').glob('traffic-*')))
 def test_large_connections_between_edge_counters(self):
  self.body=b'{"downloadTotal":987654,"connections":['+b','.join([b'{"metadata":{"host":"fixture.example"},"download":0,"upload":0}']*5000)+b'],"uploadTotal":123456}'
  d=self.sample();self.assertEqual(d['upTotal'],123456);self.assertEqual(d['downTotal'],987654)
 def test_configured_protection_floor_is_preserved(self):
  (self.p/'C/configs/memory.conf').write_text('warning_mb=20\nprotect_mb=14\ncleanup_mb=0\n');self.assertEqual(self.sample(17407)['error'],'memory_protected');self.assertEqual(self.requests,0)
 def test_memory_reserve_refuses_before_network_request(self):
  self.assertEqual(self.sample(15359)['error'],'memory_protected');self.assertEqual(self.requests,0);self.assertFalse((self.p/'ram').exists())
