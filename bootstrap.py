#!/usr/bin/env python3
"""Fetch a tagged public release, validate it, then run the device installer."""
import argparse,hashlib,re,subprocess,sys,tarfile,tempfile,urllib.request,urllib.error,shutil
from pathlib import Path
REPOSITORY='wcbspp/ShellCrash-Router-Panel'
VERSION='1.0.0'
MAX_PACKAGE=4*1024*1024

def fetch(url,limit):
 with urllib.request.urlopen(url,timeout=60) as r:
  data=r.read(limit+1)
 if len(data)>limit:raise ValueError('下载内容超过大小限制')
 return data

def extract(archive,dest,name):
 with tarfile.open(archive,'r:gz') as t:
  members=t.getmembers()
  if not members or len(members)>1000 or sum(m.size for m in members)>20*1024*1024:raise ValueError('安装包超过解压限制')
  for m in members:
   p=Path(m.name)
   if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0]!=name or not(m.isfile() or m.isdir()):raise ValueError('安装包含异常路径或链接')
  t.extractall(dest)
 return dest/name

def main():
 p=argparse.ArgumentParser(description='ShellCrash在线安装 / 离线文件准备（电脑端）');p.add_argument('device',nargs='?',choices=['ax5','k2p']);p.add_argument('--prepare-offline',action='store_true',help='下载并校验面板与内核，生成可带走的离线文件夹，不连接路由器');a,rest=p.parse_known_args()
 if sys.version_info<(3,9):p.error('需要Python3.9或更新版本')
 if not a.device:
  if not sys.stdin.isatty():p.error('请指定ax5或k2p，或在终端直接运行以选择机型')
  answer=input('选择设备：1 小米AX5 / 2 K2P：').strip().lower()
  a.device={'1':'ax5','2':'k2p','ax5':'ax5','k2p':'k2p'}.get(answer)
  if not a.device:p.error('未选择受支持机型，尚未安装')
 if not a.prepare_offline and not shutil.which('ssh'):p.error('电脑未找到ssh；请安装OpenSSH。Windows请使用WSL。')
 name='shellcrash-router-panel-'+a.device+'-'+VERSION
 base='https://github.com/'+REPOSITORY+'/releases/download/v'+VERSION
 with tempfile.TemporaryDirectory(prefix='sc-download-') as td:
  root=Path(td);print('正在下载'+a.device.upper()+'安装包 '+VERSION+'…');package=fetch(base+'/'+name+'.tar.gz',MAX_PACKAGE)
  sums=fetch(base+'/SHA256SUMS',8192).decode()
  expected=[row.split()[0] for row in sums.splitlines() if len(row.split())==2 and row.split()[1]==name+'.tar.gz']
  if len(expected)!=1 or not re.fullmatch('[a-f0-9]{64}',expected[0]) or hashlib.sha256(package).hexdigest()!=expected[0]:raise ValueError('安装包校验失败，未执行安装')
  archive=root/'package.tar.gz';archive.write_bytes(package);path=extract(archive,root,name);print('安装包SHA256校验通过。')
  if a.prepare_offline:
   output=Path.cwd()/('shellcrash-router-panel-'+a.device+'-offline-'+VERSION)
   return subprocess.run([sys.executable,str(path/'tools/prepare_offline.py'),a.device,'--output',str(output),*rest]).returncode
  return subprocess.run([sys.executable,str(path/'start.py'),*rest]).returncode
if __name__=='__main__':
 try:sys.exit(main())
 except KeyboardInterrupt:print('\n已取消。');sys.exit(130)
 except urllib.error.HTTPError as e:print('下载失败（HTTP '+str(e.code)+'）。请检查GitHub是否可访问，或从Releases下载对应安装包后运行start.py。',file=sys.stderr);sys.exit(1)
 except Exception as e:print('未完成：'+str(e),file=sys.stderr);sys.exit(1)
