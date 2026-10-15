#!/usr/bin/env python3
"""Computer-validated AX5 recovery transaction. Does not enable browser restore.

The chosen WebDAV files must match the locally inspected set byte-for-byte. A
private SSH snapshot is mandatory. The independent router worker keeps its own
rollback components and continues if this computer disconnects after arming.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

if __package__:
    from .backup_bundle import Bundle, digest, no_duplicates
else:
    from backup_bundle import Bundle, digest, no_duplicates


def plan_for(bundle, prefix, live, nonce, failure='none'):
    if not re.fullmatch(r'[a-f0-9]{8}', nonce): raise ValueError('事务编号无效')
    if prefix and not re.fullmatch(r'(?:baselines|imports|recoveries)/[A-Za-z0-9][A-Za-z0-9_.-]{0,80}', prefix):
        raise ValueError('远端前缀只能为空或 baselines/名称、imports/名称、recoveries/编号')
    if failure not in ('none', 'after-write'): raise ValueError('未知演练故障点')
    if not re.fullmatch(r'[a-f0-9]{64}', live.get('core_sha256','')) or live['core_sha256'] != live.get('configured_core_sha256'):
        raise ValueError('本机内核包与安装记录不一致，不能建立可回退事务')
    if not live.get('remote_ready') or not re.fullmatch(r'[a-f0-9]{64}', live.get('remote_fingerprint','')):
        raise ValueError('请先开启、验证并保存可连接的 WebDAV')
    if live.get('core_kind') not in ('meta','singbox') or not re.fullmatch(r'v?[0-9][A-Za-z0-9._+-]{0,39}',live.get('core_version','')):
        raise ValueError('本机运行版本记录不完整')
    if live.get('active'): raise ValueError('设备已有后台操作')
    if live.get('machine') not in ('armv7l', 'armv8l', 'aarch64'): raise ValueError('目标不是 AX5 ARM 设备')
    protect=live['protect_mb']*1024
    if protect < 12288 or live['available_kb'] < protect+3072:
        raise ValueError('内存不足以保存操作前恢复点，未暂停代理')
    m=bundle.manifest
    if not re.fullmatch(r'v?[0-9][A-Za-z0-9._+-]{0,39}',m.get('core_version','')): raise ValueError('备份内核版本无效')
    with __import__('tarfile').open(bundle.paths['application.tar.gz'],'r:gz') as archive:
        lookup={member.name.lstrip('./'):member for member in archive if member.isfile()}
        def read(name):
            if name not in lookup: raise ValueError('应用包缺少 '+name)
            with archive.extractfile(lookup[name]) as f: return f.read(2_000_000)
        info=read('backup.info').decode('ascii')
        if 'model=AX5' not in info.splitlines(): raise ValueError('应用包内部机型不匹配')
        env_hash=re.search(r'''(?m)^HASH=['"]?([a-f0-9]{64})['"]?\s*$''',read('cache/core.env').decode())
        if not env_hash or env_hash[1]!=m['core_sha256']:
            raise ValueError('内核环境记录与所选内核不一致')
        if 'cache/core.sha256' in lookup:
            app_hash=read('cache/core.sha256').decode().strip()
        else:
            # Earlier exports stored HASH only in core.env; do not invent it.
            app_hash=env_hash[1]
        if app_hash!=m['core_sha256']:
            raise ValueError('应用内核记录与所选内核不一致')
        if read('configs/enabled').strip() not in (b'0', b'1'): raise ValueError('启动状态无效')
        json.loads(read('configs/config.json'),object_pairs_hook=no_duplicates)
    app=bundle.details['application.tar.gz']['unpacked_size']
    runtime=bundle.details['runtime-assets.tar.gz']['unpacked_size']
    core=bundle.details['core.tar.gz']['unpacked_size']
    changing=m['core_sha256']!=live['core_sha256']
    records={r['name']:r for r in m['files']}
    peak=app+runtime+core+records['application.tar.gz']['size']+records['runtime-assets.tar.gz']['size']+2*1024*1024
    if changing: peak+=live['core_size']+records['core.tar.gz']['size']
    # Count freed application blocks, leave a fixed flash working reserve.
    required_flash=app+(records['core.tar.gz']['size']-live['core_size'] if changing else 0)+524288
    if required_flash>(live['flash_free_kb']+live['application_kb'])*1024:
        raise ValueError('替换应用后闪存仍不足，未暂停代理')
    result=dict(id=nonce,manifest_sha256=digest(bundle.root/'manifest.json'),
                previous_core_sha256=live['core_sha256'],core_sha256=m['core_sha256'],
                target_core_version=m['core_version'],
                remote_fingerprint=live['remote_fingerprint'],protect_kb=protect,peak_bytes=peak,
                boot_core_bytes=core,boot_private_kb=live.get('private_rss_kb',0)+1024,
                previous_core_kind=live['core_kind'],previous_core_version=live['core_version'],rehearsal_failure=failure)
    for name,key in [('application.tar.gz','application'),('runtime-assets.tar.gz','runtime'),('core.tar.gz','core')]:
        r=records[name];relative=r.get('path',name)
        if not re.fullmatch(r'[A-Za-z0-9_./-]+',relative): raise ValueError('恢复路径含不支持的字符')
        path=(prefix+'/' if prefix else '')+relative
        result.update({key+'_path':path,key+'_size':r['size'],key+'_sha256':r['sha256']})
    return result


class Device:
    def __init__(self,host,user='root',port=22,control_path=None,host_alias=None):
        if not re.fullmatch(r'[A-Za-z0-9.-]+',host) or not re.fullmatch(r'[A-Za-z0-9_-]+',user): raise ValueError('SSH 目标无效')
        self.argv=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8','-p',str(port)]
        if control_path: self.argv+=['-S',str(control_path)]
        if host_alias: self.argv+=['-o','HostKeyAlias='+host_alias]
        self.argv+=[user+'@'+host]

    def run(self,command,data=None,timeout=25):
        return subprocess.run(self.argv+[command],input=data,capture_output=True,timeout=timeout,check=True).stdout

    def live(self):
        code='''local M=dofile('/data/ShellCrash/ax5/common.lua');local s=M.state();local e=M.exec
local h=e("openssl dgst -sha256 /data/ShellCrash/cache/core-armv7.tar.gz"):match('(%x+)%s*$')
local remote=e([[C=/data/ShellCrash;D=/tmp/ShellCrash;. "$C/ax5/remote.sh";remote_transfer_ready && remote_fingerprint]])
local stat=M.read('/proc/'..s.pid..'/statm');local _,resident,shared=stat:match('^(%d+)%s+(%d+)%s+(%d+)');local private=resident and math.max(0,tonumber(resident)-tonumber(shared))*4 or 0
print(M.encode({machine=e('uname -m'):gsub('%s+$',''),active=s.active,protect_mb=M.limits().protect_mb,available_kb=s.available_kb,private_rss_kb=private,core_kind=s.core_kind,core_version=s.core_version,core_sha256=h,configured_core_sha256=M.read(M.C..'/cache/core.sha256'):gsub('%s+$',''),core_size=tonumber(e('wc -c < /data/ShellCrash/cache/core-armv7.tar.gz')),remote_ready=#remote==65,remote_fingerprint=remote:gsub('%s+$',''),flash_free_kb=tonumber(e("df -Pk /data | awk 'END{print $4}'")),application_kb=tonumber(e("du -sk /data/ShellCrash/ax5 /data/ShellCrash/ui /data/ShellCrash/configs /data/ShellCrash/ruleset /data/ShellCrash-tool /data/ShellCrash/cache/targets | awk '{n+=$1}END{print n}'"))}))'''
        return json.loads(self.run('lua -e '+shlex.quote(code)))

    def snapshot(self,path):
        # No gzip working buffer on the router; preserve original private links
        # for emergency manual recovery, never feed this raw snapshot to Bundle.
        command='tar -cf - -C / data/ShellCrash data/ShellCrash-tool etc/init.d/shellcrash'
        proc=subprocess.Popen(self.argv+[command],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        count=0
        try:
            with path.open('xb') as out:
                path.chmod(0o600)
                with gzip.GzipFile(fileobj=out,mode='wb',compresslevel=3) as compressed:
                    while True:
                        block=proc.stdout.read(131072)
                        if not block: break
                        count+=len(block)
                        if count>80_000_000: raise ValueError('操作前快照超过预算')
                        compressed.write(block)
            error=proc.stderr.read()
            if proc.wait(timeout=20): raise RuntimeError('保存操作前快照失败：'+error.decode(errors='replace')[:200])
        finally:
            if proc.poll() is None: proc.kill();proc.wait()
        with gzip.open(path,'rb') as f:
            verified=0
            for block in iter(lambda:f.read(131072),b''): verified+=len(block)
        if verified!=count: raise ValueError('操作前快照校验失败')
        return {'bytes':path.stat().st_size,'sha256':digest(path),'private_credentials_included':True}


def restore(device,bundle,receipt_dir,prefix,confirm,failure='none',limit=420):
    receipt_dir=Path(receipt_dir);receipt_dir.mkdir(mode=0o700,parents=True,exist_ok=False)
    nonce=__import__('secrets').token_hex(4);plan=plan_for(bundle,prefix,device.live(),nonce,failure)
    if confirm!=plan['manifest_sha256']: raise ValueError('确认值与所选清单不一致，未执行恢复')
    snapshot=device.snapshot(receipt_dir/'before-private.tar.gz')
    (receipt_dir/'snapshot.json').write_text(json.dumps(snapshot,indent=2))
    worker=Path(__file__).resolve().parents[1]/'profiles/ax5/ax5/restore-worker.sh'
    # Packaged computer tool also works when profile source is not present.
    if not worker.exists(): worker=Path(__file__).resolve().parents[1]/'ax5/restore-worker.sh'
    x='/tmp/sc-restore-'+nonce
    device.run('umask 077;mkdir '+x)
    device.run('cat > '+x+'/worker.sh;chmod 700 '+x+'/worker.sh;sh -n '+x+'/worker.sh',worker.read_bytes())
    device.run('cat > '+x+'/archive-validator.lua',(worker.parent/'restore-archive.lua').read_bytes())
    device.run('cat > '+x+'/plan', ''.join(str(k)+'='+str(v)+'\n' for k,v in plan.items()).encode())
    (receipt_dir/'plan.json').write_text(json.dumps(plan,indent=2))
    # Stock AX5 lacks nohup. Ignore HUP before exec and detach all descriptors;
    # the copied worker can finish or roll back after this SSH client exits.
    device.run("(trap '' HUP;exec sh "+x+'/worker.sh '+x+') > '+x+'/worker.log 2>&1 < /dev/null &')
    end=time.monotonic()+limit;last=''
    while time.monotonic()<end:
        raw=device.run('if [ -f '+x+'/result.json ];then cat '+x+'/result.json;else tail -1 '+x+'/events 2>/dev/null || :;fi',timeout=15).decode().strip()
        if raw.startswith('{'):
            result=json.loads(raw);(receipt_dir/'result.json').write_text(json.dumps(result,indent=2))
            (receipt_dir/'worker.log').write_bytes(device.run('cat '+x+'/worker.log'))
            (receipt_dir/'events').write_bytes(device.run('cat '+x+'/events'))
            return result
        if raw and raw!=last: print(raw.split(' ',1)[-1],flush=True);last=raw
        time.sleep(2)
    raise TimeoutError('恢复仍在设备后台进行；请保留事务目录 '+x+' 并查询 result.json，勿重复提交')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('bundle',type=Path);p.add_argument('--host',required=True);p.add_argument('--user',default='root');p.add_argument('--port',type=int,default=22)
    p.add_argument('--control-path');p.add_argument('--host-alias');p.add_argument('--remote-prefix',default='')
    p.add_argument('--apply',action='store_true');p.add_argument('--confirm-manifest');p.add_argument('--receipt-dir',type=Path)
    p.add_argument('--rehearsal-failure',choices=['none','after-write'],default='none')
    a=p.parse_args();device=Device(a.host,a.user,a.port,a.control_path,a.host_alias)
    with Bundle(a.bundle,'AX5') as bundle:
        if not a.apply:
            plan=plan_for(bundle,a.remote_prefix,device.live(),'00000000',a.rehearsal_failure)
            print(json.dumps({'manifest_sha256':plan['manifest_sha256'],'core_change':plan['core_sha256']!=plan['previous_core_sha256'],'peak_bytes_after_stop':plan['peak_bytes'],'device_changed':False},ensure_ascii=False));return
        if not a.receipt_dir or not a.confirm_manifest: p.error('执行需要 --receipt-dir 和 --confirm-manifest')
        result=restore(device,bundle,a.receipt_dir,a.remote_prefix,a.confirm_manifest,a.rehearsal_failure)
        print(json.dumps(result,ensure_ascii=False));raise SystemExit(0 if result['state']=='done' else 1)

if __name__=='__main__': main()
