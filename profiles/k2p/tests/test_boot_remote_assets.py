import hashlib,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class BootRemoteAssets(unittest.TestCase):
 def asset(self,enabled=True,remote=True,local=False,bad=False):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'starts').mkdir();(p/'configs').mkdir();(p/'work').mkdir()
   data=b'verified rules';(p/'payload').write_bytes(data);h=hashlib.sha256(data).hexdigest()
   if local:(p/'rules').write_bytes(data)
   (p/'configs/subscription-ca.pem').write_text('')
   helper='''remote_ready(){ [ "$ENABLED" = 1 ]; }
remote_fetch(){ remote_ready || return 2;echo fetch >> "$C/calls";[ "$REMOTE_OK" = 1 ] || return 1;cp "$C/payload" "$4"; }
remote_has(){ remote_ready && [ "$REMOTE_OK" = 1 ]; }
remote_put(){ remote_ready || return 2;echo put >> "$C/calls"; }
mirror_base(){ :; }
'''
   (p/'starts/mirror_lib.sh').write_text(helper)
   body='''C="$1";. "$2";logger(){ :; };curl(){ echo public >> "$C/calls";cp "$C/payload" "$C/work/cn.new";[ "$BAD" != 1 ] || echo corrupt > "$C/work/cn.new"; };domain_asset_ensure "$3" "$C/rules" "$C/work"'''
   r=subprocess.run(['sh','-c',body,'fixture',str(p),str(ROOT/'payload/starts/domain_asset.sh'),h],capture_output=True,text=True,env={**os.environ,'ENABLED':'1' if enabled else '0','REMOTE_OK':'1' if remote else '0','BAD':'1' if bad else '0'})
   calls=(p/'calls').read_text().splitlines() if (p/'calls').exists() else []
   return r.returncode,calls,(p/'rules').read_bytes() if (p/'rules').exists() else None
 def test_valid_ram_cache_never_connects(self):self.assertEqual(self.asset(local=True),(0,[],b'verified rules'))
 def test_remote_before_public(self):self.assertEqual(self.asset(),(0,['fetch'],b'verified rules'))
 def test_missing_remote_falls_back_and_publishes_verified_file(self):self.assertEqual(self.asset(remote=False),(0,['fetch','public','put'],b'verified rules'))
 def test_disabled_never_fetches_or_uploads(self):self.assertEqual(self.asset(enabled=False),(0,['public'],b'verified rules'))
 def test_corrupt_public_response_never_publishes(self):
  rc,calls,data=self.asset(remote=False,bad=True);self.assertNotEqual(rc,0);self.assertNotIn('put',calls);self.assertIsNone(data)

 def test_boot_delay_precedes_download_and_is_consumed_once(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'configs').mkdir();(p/'configs/ShellCrash.cfg').write_text('start_delay=10\n')
   source=(ROOT/'payload/starts/panel_boot.sh').read_text();block=source[source.index('if [ "$1" = boot ];then'):source.index('mount -t tmpfs')]
   block=block.replace('/tmp/sc-admin/events.log',str(p/'events'))
   script='CRASHDIR="$1";shift;sleep(){ echo wait-$1 >> "$CRASHDIR/calls"; };\n'+block+'\necho download-$SC_BOOT_DELAY_APPLIED >> "$CRASHDIR/calls"'
   r=subprocess.run(['sh','-c',script,'fixture',str(p),'boot'],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((p/'calls').read_text().splitlines(),['wait-10','download-1'])
   condition=(ROOT/'payload/starts/afstart.sh').read_text().split('#延迟启动\n',1)[1].split('#设置循环',1)[0]
   script='TMPDIR="$1";start_delay=10;SC_BOOT_DELAY_APPLIED=1;logger(){ :; };sleep(){ echo duplicate; };'+condition
   r=subprocess.run(['sh','-c',script,'fixture',str(p)],capture_output=True,text=True);self.assertEqual(r.stdout,'')
if __name__=='__main__':unittest.main()
