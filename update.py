#!/usr/bin/env python3
"""Upgrade an existing K2P panel with a private client backup and on-device rollback."""
import argparse,io,ipaddress,re,shlex,subprocess,sys,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description='更新已有 K2P ShellCrash 面板源码')
 p.add_argument('--host-key-alias',help='SSH 转发时使用已保存的主机标识');p.add_argument('--router',required=True);p.add_argument('--user',default='admin');p.add_argument('--port',type=int,default=22);p.add_argument('--check-only',action='store_true');p.add_argument('--backup-dir',type=Path,default=Path.home()/'ShellCrash-backups');a=p.parse_args()
 if (ROOT/'DEVICE').read_text().strip()!='k2p':raise ValueError('AX5 更新使用 deploy.py，由其原安装器识别已有部署')
 host=str(ipaddress.IPv4Address(a.router))
 if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]{0,31}',a.user) or not 1<=a.port<=65535:raise ValueError('SSH 参数无效')
 if a.host_key_alias and not re.fullmatch(r'[A-Za-z0-9.-]{1,253}',a.host_key_alias):raise ValueError('SSH 主机标识无效')
 subprocess.run([sys.executable,str(ROOT/'tools/verify_package.py'),str(ROOT)],check=True)
 with tempfile.TemporaryDirectory(prefix='sc-update-') as td:
  opts=['-p',str(a.port),'-o','ConnectTimeout=10','-o','ControlMaster=auto','-o','ControlPersist=300','-o','ControlPath='+td+'/ssh'];opts+=['-o','HostKeyAlias='+a.host_key_alias] if a.host_key_alias else [];ssh=['ssh',*opts,a.user+'@'+host];remote='/tmp/sc-update-'+Path(td).name;q=shlex.quote(remote)
  data=io.BytesIO()
  with tarfile.open(fileobj=data,mode='w:gz') as t:
   for name in ['payload','tools/update.sh','tools/legacy-migration.sha256']:
    path=ROOT/name
    for f in [path] if path.is_file() else sorted(path.rglob('*')):
     if f.is_file():
      if f.is_symlink():raise ValueError('更新包含软链接')
      t.add(f,arcname=str(f.relative_to(ROOT)),recursive=False)
  try:
   subprocess.run([*ssh,'umask 077; mkdir '+q+' && tar -xzf - -C '+q],input=data.getvalue(),check=True)
   subprocess.run([*ssh,'sh '+q+'/tools/update.sh --check'],check=True)
   if a.check_only:print('检查通过，没有更新');return 0
   a.backup_dir.mkdir(parents=True,exist_ok=True);backup=a.backup_dir/('shellcrash-before-update-'+host+'-'+Path(td).name+'.tar.gz')
   with backup.open('xb') as f:
    backup.chmod(0o600)
    subprocess.run([*ssh,'/etc/storage/ShellCrash/starts/backup-app.sh local >/dev/null && cat /tmp/sc-admin/application-backup.tar.gz'],stdout=f,check=True)
   with tarfile.open(backup) as t:
    if not t.getnames():raise ValueError('备份无效，未更新')
   subprocess.run([*ssh,'sh '+q+'/tools/update.sh --apply'],check=True)
   print('更新完成；安装前备份：'+str(backup.resolve()));return 0
  finally:
   subprocess.run([*ssh,'rm -rf '+q],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   subprocess.run(['ssh',*opts,'-O','exit',a.user+'@'+host],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':
 try:sys.exit(main())
 except (OSError,ValueError,subprocess.CalledProcessError,tarfile.TarError) as e:print('未完成：'+str(e),file=sys.stderr);sys.exit(1)
