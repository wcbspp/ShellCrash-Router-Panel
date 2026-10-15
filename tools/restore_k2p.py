#!/usr/bin/env python3
"""K2P same-core recovery prototype; does not enable browser restoration."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import tarfile
import time
if __package__:
    from .backup_bundle import Bundle, digest, no_duplicates
    from .restore_ax5 import Device as SSHDevice
else:
    from backup_bundle import Bundle, digest, no_duplicates
    from restore_ax5 import Device as SSHDevice


def plan_for(bundle, prefix, live, nonce, failure='none'):
    if bundle.manifest['model']!='K2P': raise ValueError('只能恢复 K2P 备份')
    if not re.fullmatch(r'[a-f0-9]{8}',nonce): raise ValueError('事务编号无效')
    if prefix and not re.fullmatch(r'(?:baselines|imports|recoveries)/[A-Za-z0-9][A-Za-z0-9_.-]{0,80}',prefix): raise ValueError('远端目录无效')
    if failure not in ('none','after-write'): raise ValueError('未知故障点')
    if live['machine']!='mips' or live['arch']!='mipsle-softfloat': raise ValueError('不是支持的 K2P 架构')
    if live['active'] or not live['remote_ready']: raise ValueError('后台忙或 WebDAV 未开启、验证及连接')
    if not live.get('installed_program_complete'): raise ValueError('当前 ShellCrash 程序文件不齐，不能建立完整回退点')
    if not re.fullmatch(r'[a-f0-9]{64}',live['remote_fingerprint']): raise ValueError('连接身份无效')
    protect=live['protect_mb']*1024
    if protect<12288 or live['available_kb']<protect+3072: raise ValueError('内存不足，未暂停服务')
    m=bundle.manifest
    if m['core_sha256']!=live['core_sha256']: raise ValueError('K2P 原型目前只验证相同内核，不执行跨版本恢复')
    if not re.fullmatch(r'[0-9][0-9.]{0,29}',m.get('core_version','')) or m['core_version']!=live['core_version']: raise ValueError('内核版本不一致')
    with tarfile.open(bundle.paths['core.tar.gz'],'r:gz') as archive:
        member=next(x for x in archive if x.isfile())
        if not re.fullmatch(r'(?:\./)?CrashCore',member.name): raise ValueError('不支持的内核成员路径')
        h=hashlib.sha256()
        with archive.extractfile(member) as f:
            for block in iter(lambda:f.read(131072),b''):h.update(block)
        binary_hash=h.hexdigest();binary_size=member.size;core_member=member.name
    if binary_hash!=live['binary_sha256']: raise ValueError('运行中的内核与已检查备份不一致')
    with tarfile.open(bundle.paths['application.tar.gz'],'r:gz')as archive:
        members={x.name.removeprefix('./'):x for x in archive if x.isfile()}
        def read(name):
            if name not in members or members[name].size>2_000_000:raise ValueError('缺少必要元数据或文件过大：'+name)
            with archive.extractfile(members[name])as f:return f.read()
        info=dict(line.split('=',1)for line in read('backup.info').decode().splitlines()if '='in line)
        installed=dict(line.split('=',1)for line in read('configs/core-installed.info').decode().splitlines()if '='in line)
        if info.get('model')!='K2P' or installed.get('sha256')!=m['core_sha256'] or installed.get('version')!=m['core_version'] or installed.get('arch')!='mipsle-softfloat': raise ValueError('应用内部机型或内核记录不一致')
        for key in ('enabled','autostart'):
            if info.get(key)not in ('0','1'): raise ValueError('旧备份缺少启动状态，请先重新创建完整备份')
        if info.get('traffic_mode')not in ('rule','direct','global'): raise ValueError('备份缺少流量模式')
        config=json.loads(read('jsons/config.json'),object_pairs_hook=no_duplicates)
        if not isinstance(config,dict) or not isinstance(config.get('outbounds'),list):raise ValueError('配置无效')
    for key in ('enabled','autostart'):
        if live[key]not in (0,1):raise ValueError('当前启动状态无效')
    if live['traffic_mode']not in ('rule','direct','global'):raise ValueError('当前流量模式无效')
    records={r['name']:r for r in m['files']}
    app=bundle.details['application.tar.gz']['unpacked_size'];runtime=bundle.details['runtime-assets.tar.gz']['unpacked_size']
    # No compressed core on tmpfs. Previous compact rollback archives already
    # exist when the worker checks the actual free budget after stopping.
    peak=binary_size+app+runtime+records['application.tar.gz']['size']+records['runtime-assets.tar.gz']['size']+6*1024*1024
    result=dict(id=nonce,manifest_sha256=digest(bundle.root/'manifest.json'),remote_fingerprint=live['remote_fingerprint'],
                core_sha256=m['core_sha256'],core_version=m['core_version'],core_member=core_member,binary_size=binary_size,binary_sha256=binary_hash,
                protect_kb=protect,peak_bytes=peak,tmp_bytes=peak,
                previous_enabled=live['enabled'],previous_autostart=live['autostart'],previous_mode=live['traffic_mode'],
                target_enabled=info['enabled'],target_autostart=info['autostart'],target_mode=info['traffic_mode'],rehearsal_failure=failure)
    for name,key in [('application.tar.gz','application'),('runtime-assets.tar.gz','runtime'),('core.tar.gz','core')]:
        r=records[name];relative=r.get('path',name)
        if not re.fullmatch(r'[A-Za-z0-9_./-]+',relative): raise ValueError('组件路径包含不支持字符')
        result.update({key+'_path':(prefix+'/'if prefix else '')+relative,key+'_size':r['size'],key+'_sha256':r['sha256']})
    return result


class Device(SSHDevice):
    def live(self):
        script='''PATH=/usr/sbin:/usr/bin:/sbin:/bin
C=/etc/storage/ShellCrash;D=/tmp/sc-admin
. "$C/starts/resource_health.sh";resource_limits
. "$C/starts/core_release.sh";release_valid "$C/configs/core-installed.info" || exit 1
pid=$(pidof CrashCore|awk '{print $1}');[ -n "$pid" ] || exit 1
printf 'machine=%s\\narch=%s\\ncore_sha256=%s\\ncore_version=%s\\n' "$(uname -m)" "$(release_get arch "$C/configs/core-installed.info")" "$(release_get sha256 "$C/configs/core-installed.info")" "$(release_get version "$C/configs/core-installed.info")"
printf 'binary_sha256=%s\\nprotect_mb=%s\\navailable_kb=%s\\n' "$(sha256sum /proc/$pid/exe|awk '{print $1}')" "$rh_protect_mb" "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)"
a=1;[ ! -f "$C/.dis_startup" ] || a=0;e=1;[ ! -f "$C/configs/panel-disabled" ] || e=0
mode=$(cat /tmp/ShellCrash/traffic-mode 2>/dev/null);case "$mode" in rule|direct|global) :;;*)mode=rule;;esac
printf 'autostart=%s\\nenabled=%s\\ntraffic_mode=%s\\n' "$a" "$e" "$mode"
active=0;owner=$(cat "$D/operation.lock/owner" 2>/dev/null);[ -z "$owner" ] || { ! kill -0 "$owner" 2>/dev/null || active=1; }
printf 'active=%s\\n' "$active"
complete=1;for name in start.sh menu.sh menus/bot_tg_service.sh;do [ -s "$C/$name" ] || complete=0;done
printf 'installed_program_complete=%s\\n' "$complete"
. "$C/starts/remote.sh"
if remote_transfer_ready && [ "$(remote_transport)" = webdav ];then printf 'remote_ready=1\\nremote_fingerprint=%s\\n' "$(remote_fingerprint)";else printf 'remote_ready=0\\nremote_fingerprint=\\n';fi
'''
        values=dict(line.split('=',1)for line in self.run(script,timeout=40).decode().splitlines()if '='in line)
        for key in ['protect_mb','available_kb','autostart','enabled']: values[key]=int(values[key])
        for key in ['active','remote_ready','installed_program_complete']:values[key]=values[key]=='1'
        return values

    def snapshot(self,path):
        # Original Storage includes private credentials; keep only on this PC.
        proc=subprocess.Popen(self.argv+['tar -cf - -C / etc/storage'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        total=0
        try:
            with path.open('xb')as out:
                path.chmod(0o600)
                with gzip.GzipFile(fileobj=out,mode='wb',compresslevel=3)as compressed:
                    for block in iter(lambda:proc.stdout.read(65536),b''):
                        total+=len(block)
                        if total>16_000_000: raise ValueError('Storage 快照超出预算')
                        compressed.write(block)
            err=proc.stderr.read()
            if proc.wait(timeout=15):raise RuntimeError('Storage 快照失败：'+err.decode(errors='replace')[:120])
        finally:
            if proc.poll()is None:proc.kill();proc.wait()
        with gzip.open(path,'rb')as f:
            checked=0
            for block in iter(lambda:f.read(65536),b''):checked+=len(block)
        if checked!=total:raise ValueError('私有快照读回失败')
        return dict(bytes=path.stat().st_size,sha256=digest(path),private_credentials_included=True)


def restore(device,bundle,receipt_dir,prefix,confirm,failure='none',limit=480):
    receipt_dir=Path(receipt_dir);receipt_dir.mkdir(mode=0o700,parents=True,exist_ok=False)
    nonce=secrets.token_hex(4);plan=plan_for(bundle,prefix,device.live(),nonce,failure)
    if confirm!=plan['manifest_sha256']:raise ValueError('清单确认值不一致，未执行')
    snapshot=device.snapshot(receipt_dir/'before-storage.private.tar.gz')
    (receipt_dir/'snapshot.json').write_text(json.dumps(snapshot,indent=2))
    worker=Path(__file__).resolve().parents[1]/'profiles/k2p/payload/starts/restore-worker.sh'
    if not worker.exists():worker=Path(__file__).resolve().parents[1]/'payload/starts/restore-worker.sh'
    x='/tmp/sc-restore-'+nonce
    device.run('umask 077;mkdir '+x)
    device.run('cat > '+x+'/worker.sh;chmod 700 '+x+'/worker.sh;sh -n '+x+'/worker.sh',worker.read_bytes())
    device.run('cat > '+x+'/plan',''.join(str(k)+'='+str(v)+'\n'for k,v in plan.items()).encode())
    (receipt_dir/'plan.json').write_text(json.dumps(plan,indent=2))
    device.run("(trap '' HUP;exec sh "+x+'/worker.sh '+x+') > '+x+'/worker.log 2>&1 < /dev/null &')
    end=time.monotonic()+limit;last=''
    while time.monotonic()<end:
        raw=device.run('if [ -f '+x+'/result.json ];then cat '+x+'/result.json;else tail -1 '+x+'/events 2>/dev/null || :;fi').decode().strip()
        if raw.startswith('{'):
            result=json.loads(raw);(receipt_dir/'result.json').write_text(json.dumps(result,indent=2))
            (receipt_dir/'worker.log').write_bytes(device.run('cat '+x+'/worker.log'))
            (receipt_dir/'events').write_bytes(device.run('cat '+x+'/events'))
            return result
        if raw and raw!=last:print(raw.split(' ',1)[-1],flush=True);last=raw
        time.sleep(3)
    raise TimeoutError('设备任务仍可能在执行，查询 '+x+'/result.json，勿重复提交')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('bundle',type=Path)
    p.add_argument('--host',required=True);p.add_argument('--user',default='admin');p.add_argument('--port',type=int,default=22)
    p.add_argument('--control-path');p.add_argument('--host-alias');p.add_argument('--remote-prefix',default='')
    p.add_argument('--apply',action='store_true');p.add_argument('--confirm-manifest');p.add_argument('--receipt-dir',type=Path)
    p.add_argument('--rehearsal-failure',choices=['none','after-write'],default='none');a=p.parse_args()
    d=Device(a.host,a.user,a.port,a.control_path,a.host_alias)
    with Bundle(a.bundle,'K2P')as b:
        if not a.apply:
            plan=plan_for(b,a.remote_prefix,d.live(),'00000000',a.rehearsal_failure)
            print(json.dumps(dict(manifest_sha256=plan['manifest_sha256'],peak_bytes_after_stop=plan['peak_bytes'],device_changed=False)));return
        if not a.confirm_manifest or not a.receipt_dir:p.error('执行需要 --confirm-manifest 与 --receipt-dir')
        result=restore(d,b,a.receipt_dir,a.remote_prefix,a.confirm_manifest,a.rehearsal_failure)
        print(json.dumps(result,ensure_ascii=False));raise SystemExit(0 if result['state']=='done'else 1)
if __name__=='__main__':main()
