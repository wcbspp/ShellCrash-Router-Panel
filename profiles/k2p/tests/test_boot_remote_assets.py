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

 def test_new_installed_digest_wins_over_old_remote_and_old_local(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'configs').mkdir();(p/'starts').mkdir();(p/'work').mkdir()
   old=b'previous domain';new=b'new successful domain';oldh=hashlib.sha256(old).hexdigest();newh=hashlib.sha256(new).hexdigest()
   (p/'rules').write_bytes(old)
   (p/'configs/domain-installed.info').write_text('sha256='+newh+'\nurl=https://fixture.invalid/new.srs\ntype=direct\n')
   (p/'configs/subscription-ca.pem').write_text('')
   (p/'starts/mirror_lib.sh').write_text('remote_fetch(){ echo "$2" > "$C/requested";printf "previous domain" > "$4"; };mirror_base(){ :; };remote_ready(){ return 2; }\n')
   script='C="$1"; . "$2";logger(){ :; };curl(){ printf "new successful domain" > "$C/work/cn.new"; };domain_asset_ensure "$3" "$C/rules" "$C/work"'
   r=subprocess.run(['sh','-c',script,'fixture',str(p),str(ROOT/'payload/starts/domain_asset.sh'),oldh],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((p/'rules').read_bytes(),new)
   self.assertEqual((p/'requested').read_text().strip(),newh)
   self.assertIn(newh,(p/'configs/domain-installed.info').read_text())

 def test_malformed_installed_domain_record_cannot_fall_back_to_old_version(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'configs').mkdir();(p/'work').mkdir();(p/'rules').write_bytes(b'old valid file')
   (p/'configs/domain-installed.info').write_text('sha256=invalid\nurl=https://fixture.invalid/new.srs\ntype=direct\n')
   h=hashlib.sha256(b'old valid file').hexdigest()
   script='C="$1";. "$2";logger(){ :; };domain_asset_ensure "$3" "$C/rules" "$C/work"'
   r=subprocess.run(['sh','-c',script,'fixture',str(p),str(ROOT/'payload/starts/domain_asset.sh'),h],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertEqual((p/'rules').read_bytes(),b'old valid file')

 def test_domain_record_commit_validation_and_storage_failure_preserve_old_record(self):
  for binary_ok,save_ok in [(False,True),(True,False),(True,True)]:
   with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);(p/'configs').mkdir();(p/'starts').mkdir()
    old='sha256='+('a'*64)+'\nurl=https://fixture.invalid/old.srs\ntype=direct\n'
    (p/'configs/domain-installed.info').write_text(old);(p/'current.srs').write_bytes(b'new' * 1024)
    binary=p/'core';binary.write_text('#!/bin/sh\nexit '+('0' if binary_ok else '1')+'\n');binary.chmod(0o700)
    (p/'starts/resource_health.sh').write_text('resource_read(){ rh_available=30000;rh_protect_mb=12; }\n')
    saver=p/'starts/save_storage.sh';saver.write_text('#!/bin/sh\nexit '+('0' if save_ok else '1')+'\n');saver.chmod(0o700)
    (p/'starts/mirror_lib.sh').write_text('remote_ready(){ return 2; }\n')
    source=(ROOT/'payload/starts/domain_asset.sh').read_text().replace('/tmp/ShellCrash/CrashCore',str(binary))
    (p/'asset.sh').write_text(source)
    script='C="$1";D="$1";pidof(){ :; };. "$C/asset.sh";domain_asset_commit "$C/current.srs" https://fixture.invalid/new.srs direct'
    r=subprocess.run(['sh','-c',script,'fixture',str(p)],capture_output=True,text=True)
    if binary_ok and save_ok:
     self.assertEqual(r.returncode,0,r.stderr);self.assertIn(hashlib.sha256(b'new'*1024).hexdigest(),(p/'configs/domain-installed.info').read_text())
    else:
     self.assertNotEqual(r.returncode,0);self.assertEqual((p/'configs/domain-installed.info').read_text(),old)

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
