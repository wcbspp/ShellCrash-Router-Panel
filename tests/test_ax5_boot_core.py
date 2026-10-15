"""Real shell and HTTP: installed core SHA wins over stale/oversized peers."""
from pathlib import Path
import hashlib,http.server,io,subprocess,tarfile,tempfile,threading,unittest,shlex,shutil,os,time
ROOT=Path(__file__).resolve().parents[1]

def archive(payload):
    b=io.BytesIO()
    with tarfile.open(fileobj=b,mode='w:gz')as t:
        f=tarfile.TarInfo('CrashCore');f.size=len(payload);t.addfile(f,io.BytesIO(payload))
    return b.getvalue()

class BootInstalledAuthority(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.c=self.root/'persist';self.r=self.root/'ram';(self.c/'ax5').mkdir(parents=True);(self.c/'cache').mkdir();self.r.mkdir()
        self.expected=archive(b'new installed executable');self.old=archive(b'old remote executable');self.sha=hashlib.sha256(self.expected).hexdigest()
        outer=self
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                outer.calls.append(self.path)
                self.send_response(200)
                # Deliberately no Content-Length: firmware must bound actual bytes.
                self.end_headers()
                body=outer.expected if self.path=='/current'else outer.old if self.path=='/old'else b'x'*300000
                try:
                    for offset in range(0,len(body),4096):
                        self.wfile.write(body[offset:offset+4096]);self.wfile.flush()
                        if self.path=='/oversize':time.sleep(.002)
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        self.calls=[];self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.addCleanup(self.stop)
        text=(ROOT/'profiles/ax5/ax5/recover-core.sh').read_text().replace('. /data/ShellCrash/ax5/core-env.sh','. '+shlex.quote(str(self.c/'ax5/core-env.sh')))
        text=text.replace('18000001','65537').replace('18000000','65536')
        self.script=self.root/'recover.sh';self.script.write_text(text)
        # Emulate old curl ignoring the announced-length option, retaining real
        # HTTP streaming so the actual head limit must protect the tmpfs file.
        bindir=self.root/'bin';bindir.mkdir();curl=bindir/'curl';actual=shutil.which('curl')
        curl.write_text('#!/usr/bin/env python3\nimport os,sys\na=sys.argv[1:];i=a.index("--max-filesize");del a[i:i+2];os.execv('+repr(actual)+',['+repr(actual)+']+a)\n');curl.chmod(0o700)
        self.env=dict(os.environ,PATH=str(bindir)+':'+os.environ['PATH'])
        (self.c/'cache/core-armv7.tar.gz').write_bytes(b'previous cache must survive rejection')
    def stop(self):self.server.shutdown();self.server.server_close();self.thread.join()
    def run_recovery(self,route,remote=False):
        url='http://127.0.0.1:'+str(self.server.server_port)+route
        # The fixture remote advertises only the stale core. It must be asked for
        # the installed digest, not allowed to substitute its own latest version.
        env='C='+shlex.quote(str(self.c))+';R='+shlex.quote(str(self.r))+';HASH='+self.sha+';SOURCE='+shlex.quote(url)+';MIRROR=\n'
        env+='remote_fetch(){ printf "%s\\n" "$2" > "$R/requested-sha";'
        if remote:env+='cp '+shlex.quote(str(self.root/'remote-current'))+' "$4";return 0; }\n';(self.root/'remote-current').write_bytes(self.expected)
        else:env+='return 1; }\n'
        p=self.c/'ax5/core-env.sh';p.write_text(env);before=p.read_bytes()
        stop=threading.Event();observed=[]
        def observe():
            while not stop.is_set():
                try:observed.append((self.r/'recovered.tar.gz').stat().st_size)
                except FileNotFoundError:pass
                stop.wait(.001)
        watcher=threading.Thread(target=observe,daemon=True);watcher.start()
        try:result=subprocess.run(['sh',str(self.script)],capture_output=True,timeout=8,env=self.env)
        finally:stop.set();watcher.join()
        if route=='/oversize':self.assertGreater(max(observed,default=0),0);self.assertLessEqual(max(observed),65537)
        self.assertEqual(p.read_bytes(),before)
        self.assertEqual((self.r/'requested-sha').read_text().strip(),self.sha)
        self.assertFalse((self.r/'recovered.tar.gz').exists());self.assertFalse((self.r/'recovered.status').exists())
        return result
    def test_missing_new_remote_uses_exact_installed_public_archive(self):
        r=self.run_recovery('/current');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual((self.c/'cache/core-armv7.tar.gz').read_bytes(),self.expected);self.assertEqual(self.calls,['/current'])
    def test_old_public_archive_cannot_downgrade_or_replace_local_cache(self):
        r=self.run_recovery('/old');self.assertNotEqual(r.returncode,0)
        self.assertEqual((self.c/'cache/core-armv7.tar.gz').read_bytes(),b'previous cache must survive rejection')
    def test_lengthless_oversize_body_is_truncated_and_rejected(self):
        r=self.run_recovery('/oversize');self.assertNotEqual(r.returncode,0)
        self.assertEqual((self.c/'cache/core-armv7.tar.gz').read_bytes(),b'previous cache must survive rejection')
    def test_exact_remote_hit_does_not_contact_public(self):
        r=self.run_recovery('/current',True);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.calls,[])
if __name__=='__main__':unittest.main()
