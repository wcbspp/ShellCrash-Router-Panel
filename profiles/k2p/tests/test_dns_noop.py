import base64,subprocess,tempfile,unittest,shutil,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class DNSNoOp(unittest.TestCase):
 def execute(self,override=''):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);p=Path(self.t.name);c=p/'C';d=p/'D';(c/'configs').mkdir(parents=True);(c/'starts').mkdir();d.mkdir()
  (c/'starts/filter_compile.awk').write_bytes((ROOT/'payload/starts/filter_compile.awk').read_bytes())
  data=b'# fixture\n+.example.com\n';(c/'configs/fake_ip_filter.list').write_bytes(data);(c/'configs/ShellCrash.cfg').write_text('dns_mod=mix\ndisoverride='+override+'\n')
  (d/'upload.parts').write_text('0 '+base64.b64encode(data).decode()+'\n')
  # Model BusyBox's file argument support on macOS, without changing the script.
  b=p/'bin';b.mkdir()
  programs={
   'base64':'import base64,sys\na=sys.argv[1:];data=open(a[-1],"rb").read() if a and a[-1] not in ("-d","-D") else sys.stdin.buffer.read();sys.stdout.buffer.write(base64.b64decode(data) if "-d" in a or "-D" in a else base64.b64encode(data))',
   'stat':'import os,sys\nprint(os.stat(sys.argv[-1]).st_size)',
   'sha256sum':'import hashlib,sys\nprint(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()+"  "+sys.argv[1])',
   'pidof':'import sys\nsys.exit(1)'}
  for name,body in programs.items():
   f=b/name;f.write_text('#!'+sys.executable+'\n'+body+'\n');f.chmod(0o700)
  code='C="'+str(c)+'";D="'+str(d)+'";set -- dns fixture mix;phase(){ echo "$*"; }; fail(){ echo "failure:$*"; };configuration_core_prepare(){ echo NEEDS_APPLY;return 1; }; . "'+str(ROOT/'payload/starts/dns_update.sh')+'"'
  return p,c,d,subprocess.run(['sh','-c',code],capture_output=True,text=True,env={**os.environ,'PATH':str(b)+os.pathsep+os.environ['PATH']})
 def test_same_filter_mode_does_not_prepare_or_restart_core(self):
  p,c,d,r=self.execute();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('无需重启',r.stdout);self.assertNotIn('NEEDS_APPLY',r.stdout);self.assertFalse((d/'dns/previous.cfg').exists())
 def test_disabled_local_override_must_still_apply(self):
  p,c,d,r=self.execute('ON');self.assertNotEqual(r.returncode,0);self.assertIn('NEEDS_APPLY',r.stdout)
