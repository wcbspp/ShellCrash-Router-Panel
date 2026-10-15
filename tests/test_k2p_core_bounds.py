"""Actual HTTP streams exercise K2P archive/metadata byte and identity limits."""
from pathlib import Path
import hashlib,http.server,json,os,shlex,shutil,subprocess,tempfile,threading,time,unittest
ROOT=Path(__file__).resolve().parents[1]

class K2PDownloadBounds(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.c=self.root/'app';self.d=self.root/'state';(self.c/'starts').mkdir(parents=True);(self.c/'configs').mkdir();(self.d/'core-check').mkdir(parents=True)
        (self.c/'starts/panel_env.sh').write_text('PANEL_LAN_IP=127.0.0.1\n')
        (self.c/'starts/core_release.sh').write_bytes((ROOT/'profiles/k2p/payload/starts/core_release.sh').read_bytes())
        self.current=b'installed-new-binary'*200;self.old=b'previous-old-binary'*200;outer=self;self.calls=[]
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                outer.calls.append(self.path);self.send_response(200)
                body=outer.current if self.path=='/current'else outer.old if self.path=='/old'else b'x'*100000
                if self.path=='/truncated':self.send_header('Content-Length',str(len(body)+100))
                self.end_headers()
                try:
                    for offset in range(0,len(body),2048):
                        self.wfile.write(body[offset:offset+2048]);self.wfile.flush()
                        if self.path=='/oversize':time.sleep(.002)
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();self.addCleanup(self.stop)
        self.url='http://127.0.0.1:'+str(self.server.server_port)
        self.bin=self.root/'bin';self.bin.mkdir();actual=shutil.which('curl')
        self.shim('curl','import os,sys\na=sys.argv[1:];i=a.index("--max-filesize");del a[i:i+2];os.execv('+repr(actual)+',['+repr(actual)+']+a)')
        self.shim('stat','import sys,os\nprint(os.stat(sys.argv[-1]).st_size)')
        self.shim('sha256sum','import sys,hashlib\np=sys.argv[1];print(hashlib.sha256(open(p,"rb").read()).hexdigest()+"  "+p)')
        p=self.bin/'pidof';p.write_text('#!/bin/sh\nexit 1\n');p.chmod(0o700)
        self.env=dict(os.environ,PATH=str(self.bin)+':'+os.environ['PATH'])
        self.dest=self.root/'download'
    def shim(self,name,code):
        p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+code+'\n');p.chmod(0o700)
    def stop(self):self.server.shutdown();self.server.server_close();self.thread.join()
    def shell(self,code):
        setup='C='+shlex.quote(str(self.c))+';D='+shlex.quote(str(self.d))+';CRASHDIR=$C;. "$C/starts/core_release.sh"\n'
        return subprocess.run(['sh','-c',setup+code],env=self.env,capture_output=True,timeout=10)
    def test_lengthless_oversize_stays_bounded_and_cleans_partial_file(self):
        stop=threading.Event();observed=[]
        def observe():
            while not stop.is_set():
                try:observed.append(self.dest.stat().st_size)
                except FileNotFoundError:pass
                stop.wait(.001)
        thread=threading.Thread(target=observe,daemon=True);thread.start()
        try:r=self.shell('release_curl_bounded '+str(self.dest)+' 4096 -fsS --max-filesize 4096 '+self.url+'/oversize')
        finally:stop.set();thread.join()
        self.assertNotEqual(r.returncode,0);self.assertGreater(max(observed,default=0),0);self.assertLessEqual(max(observed),4097)
        self.assertFalse(self.dest.exists());self.assertFalse(Path(str(self.dest)+'.curl-status').exists())
    def test_exact_body_succeeds_but_transport_truncation_never_succeeds(self):
        r=self.shell('release_curl_bounded '+str(self.dest)+' '+str(len(self.current))+' -fsS --max-filesize '+str(len(self.current))+' '+self.url+'/current');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.dest.read_bytes(),self.current)
        r=self.shell('release_curl_bounded '+str(self.dest)+' 200000 -fsS --max-filesize 200000 '+self.url+'/truncated');self.assertNotEqual(r.returncode,0);self.assertFalse(self.dest.exists())
    def test_invalid_budget_does_not_touch_destination_or_network(self):
        self.dest.write_bytes(b'previous')
        for size in ['0','-1','bad','999999999']:
            r=self.shell('release_curl_bounded '+str(self.dest)+' '+shlex.quote(size)+' -fsS --max-filesize 4096 '+self.url+'/current');self.assertNotEqual(r.returncode,0);self.assertEqual(self.dest.read_bytes(),b'previous')
        self.assertEqual(self.calls,[])
    def record(self,route='/current',blob=None):
        sha=hashlib.sha256(self.current).hexdigest();blob=blob or hashlib.sha1(b'blob '+str(len(self.current)).encode()+b'\0'+self.current).hexdigest()
        record=self.c/'configs/core-installed.info';record.write_text('version=1.12.13\narch=mipsle-softfloat\nvariant=singbox\nsha256='+sha+'\narchive_size='+str(len(self.current))+'\ngit_blob='+blob+'\nurl='+self.url+route+'\n')
        (self.c/'starts/mirror_lib.sh').write_text('remote_fetch(){ printf "%s\\n" "$2" > "$D/requested-sha";return 1; }\nmirror_core_url(){ echo '+self.url+'/old; }\n')
        return record,sha
    def release(self,record):return self.shell('core_cacerts(){ : > "$D/core-check/ca.pem"; }\nrelease_download '+str(record)+' '+str(self.dest))
    def test_stale_mirror_falls_back_to_installed_sha_and_git_blob(self):
        record,sha=self.record();before=record.read_bytes();r=self.release(record);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.dest.read_bytes(),self.current);self.assertEqual(self.calls,['/old','/current']);self.assertEqual(record.read_bytes(),before);self.assertEqual((self.d/'requested-sha').read_text().strip(),sha)
    def test_only_old_sources_or_wrong_git_blob_cannot_rewrite_installed_record(self):
        record,_=self.record('/old');before=record.read_bytes();r=self.release(record);self.assertNotEqual(r.returncode,0);self.assertFalse(self.dest.exists());self.assertEqual(record.read_bytes(),before)
        record,_=self.record(blob='0'*40);before=record.read_bytes();r=self.release(record);self.assertNotEqual(r.returncode,0);self.assertEqual(record.read_bytes(),before);self.assertFalse(self.dest.exists())
    def test_metadata_uses_same_actual_byte_limit(self):
        r=self.shell('core_fetch_metadata '+self.url+'/oversize '+str(self.dest));self.assertNotEqual(r.returncode,0);self.assertFalse(self.dest.exists())
if __name__=='__main__':unittest.main()
