#!/usr/bin/env python3
"""Computer-side installer for generated AX5/K2P packages."""
import argparse,hashlib,json,ipaddress,shlex,subprocess,sys,tarfile,tempfile,io,os,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description='电脑端安装 ShellCrash Router Panel')
 p.add_argument('--router');p.add_argument('--user');p.add_argument('--port',type=int,default=22)
 p.add_argument('--check-only',action='store_true');p.add_argument('--core-file',type=Path);p.add_argument('--nodes-file',type=Path)
 p.add_argument('--backup-dir',type=Path,default=Path.home()/'ShellCrash-backups');a=p.parse_args()
 device=(ROOT/'DEVICE').read_text().strip()
 if a.core_file and not a.core_file.is_file():p.error('离线内核文件不存在')
 from tools.verify_package import verify
 verify(ROOT,[a.nodes_file,a.core_file])
 if a.core_file:
  expected=json.loads((ROOT/'CORE.json').read_text())
  if a.core_file.stat().st_size!=expected['archive_size'] or hashlib.sha256(a.core_file.read_bytes()).hexdigest()!=expected['sha256']:raise ValueError('离线内核的架构、版本或校验不匹配；未连接路由器')
 if device=='k2p':
  cmd=[sys.executable,str(ROOT/'tools/deploy.py')]
  for arg,value in [('router',a.router),('user',a.user),('port',a.port),('core-file',a.core_file),('nodes-file',a.nodes_file),('backup-dir',a.backup_dir)]:
   if value is not None:cmd+=['--'+arg,str(value)]
  if a.check_only:cmd+=['--check-only']
  return subprocess.run(cmd).returncode
 if device!='ax5':raise ValueError('未知机型')
 if a.nodes_file:raise ValueError('AX5 安装后在面板填写订阅；离线首次安装保持直连，不读取节点文件')
 host=str(ipaddress.IPv4Address(a.router or input('路由器地址 [192.168.31.1]：').strip() or '192.168.31.1'))
 user=a.user or 'root'
 import re
 if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]{0,31}',user) or not 1<=a.port<=65535:raise ValueError('SSH 参数无效')
 if not shutil.which('ssh'):raise ValueError('找不到 OpenSSH；Windows 请在 WSL 运行')
 a.backup_dir.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='sc-ax5-') as td:
  opts=['-p',str(a.port),'-o','HostKeyAlgorithms=+ssh-rsa','-o','ConnectTimeout=10','-o','ControlMaster=auto','-o','ControlPersist=300','-o','ControlPath='+td+'/ssh']
  ssh=['ssh',*opts,user+'@'+host];remote='/tmp/sc-ax5-'+Path(td).name;quote=shlex.quote(remote)
  data=io.BytesIO()
  with tarfile.open(fileobj=data,mode='w:gz') as t:
   for f in sorted(ROOT.rglob('*')):
    if f.is_file() and '__pycache__' not in f.parts and f.suffix!='.pyc' and not(a.core_file and f.resolve()==a.core_file.resolve()):
     if f.is_symlink():raise ValueError('安装包含软链接')
     t.add(f,arcname='package/'+str(f.relative_to(ROOT)),recursive=False)
   if a.core_file:t.add(a.core_file,arcname='core-offline.tar.gz',recursive=False)
  try:
   subprocess.run([*ssh,'umask 077; mkdir '+quote+' && tar -xzf - -C '+quote],input=data.getvalue(),check=True)
   base='cd '+quote+'/package && '
   subprocess.run([*ssh,base+'sh install.sh --check'],check=True)
   if a.check_only:print('检查通过，没有安装或重启服务');return 0
   backup=a.backup_dir/('shellcrash-before-ax5-'+host+'-'+Path(td).name+'.tar.gz')
   # The installer retains its own transactional rollback. Also keep a client copy.
   with backup.open('xb') as f:
    backup.chmod(0o600)
    subprocess.run([*ssh,"set --; for f in data/ShellCrash data/ShellCrash-tool etc/init.d/shellcrash usr/lib/lua/luci/controller/web/shellcrash.lua usr/lib/lua/luci/view/web/shellcrash.htm usr/lib/lua/luci/view/web/inc/header.htm; do [ ! -e /$f ] || set -- \"$@\" \"$f\"; done; [ \"$#\" -gt 0 ] && tar -czf - -C / \"$@\""],stdout=f,check=True)
   with tarfile.open(backup) as t:
    if not t.getnames():raise ValueError('安装前备份为空')
   env='SC_OFFLINE_CORE='+shlex.quote(remote+'/core-offline.tar.gz')+' ' if a.core_file else ''
   subprocess.run([*ssh,base+env+'sh install.sh auto'],check=True)
   print('安装完成：登录小米后台 → ShellCrash；安装前备份：'+str(backup.resolve()))
   return 0
  finally:
   subprocess.run([*ssh,'rm -rf '+quote],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   subprocess.run(['ssh',*opts,'-O','exit',user+'@'+host],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':
 try:sys.exit(main())
 except (OSError,ValueError,subprocess.CalledProcessError,tarfile.TarError) as e:print('未完成：'+str(e),file=sys.stderr);sys.exit(1)
