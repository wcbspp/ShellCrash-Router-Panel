"""Shared fallback policy with real HTTP, including lengthless oversized bodies."""
import hashlib, os, subprocess, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
SOURCE=Path(__file__).resolve().parents[1]/'shared/lib/rule-source.sh'
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  self.server.calls+=1;self.send_response(200);self.end_headers()
  try:self.wfile.write(self.server.payload)
  except (BrokenPipeError,ConnectionResetError):pass
class RuleSource(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name)
  self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.server.payload=b'valid compatible rules';self.server.calls=0
  self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
 def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
 def fetch(self,expected,latest=0,compatible=True,limit=1024):
  script='. "$1"; pidof(){ return 1; }; rule_source_validate(){ '+('return 0;' if compatible else 'return 1;')+' }; rule_source_fetch "$2" "$3" "$4" "$5" "$6"'
  return subprocess.run(['sh','-c',script,'test',str(SOURCE),'http://127.0.0.1:'+str(self.server.server_port)+'/rules',str(self.p/'rules'),expected,str(limit),str(latest)],env=dict(os.environ,C=str(self.p)),capture_output=True,text=True,timeout=10)
 def test_existing_digest_is_kept_without_an_update_marker(self):
  r=self.fetch(hashlib.sha256(self.server.payload).hexdigest(),1);self.assertEqual(r.returncode,0,r.stderr);self.assertFalse((self.p/'rules.updated').exists())
 def test_latest_compatible_digest_is_recorded(self):
  r=self.fetch('0'*64,1);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((self.p/'rules.updated').read_text().strip(),hashlib.sha256(self.server.payload).hexdigest())
 def test_incompatible_latest_is_rejected(self):
  r=self.fetch('0'*64,1,False);self.assertNotEqual(r.returncode,0);self.assertFalse((self.p/'rules.updated').exists())
 def test_strict_restore_does_not_update(self):
  r=self.fetch('0'*64);self.assertNotEqual(r.returncode,0);self.assertFalse((self.p/'rules.updated').exists())
 def test_lengthless_response_cannot_exceed_the_memory_budget(self):
  self.server.payload=b'x'*1048576
  r=self.fetch('',limit=4096);self.assertNotEqual(r.returncode,0);self.assertFalse((self.p/'rules').exists())
 def test_pinned_sagernet_ref_keeps_repository_and_dataset(self):
  r=subprocess.run(['sh','-c','. "$1";rule_source_latest_url "$2"','test',str(SOURCE),'https://raw.githubusercontent.com/SagerNet/sing-geosite/'+('a'*40)+'/geosite-cn.srs'],capture_output=True,text=True)
  self.assertEqual(r.stdout.strip(),'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs')
if __name__=='__main__':unittest.main()
