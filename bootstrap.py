#!/usr/bin/env python3
"""Fetch a tagged public release, validate it, then run the device installer."""
import argparse,hashlib,re,subprocess,sys,tarfile,tempfile,urllib.request
from pathlib import Path
REPOSITORY='wcbspp/ShellCrash-Router-Panel'
VERSION='1.0.0-rc.3'
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
 p=argparse.ArgumentParser(description='在线安装 ShellCrash Router Panel（电脑端）');p.add_argument('device',choices=['ax5','k2p']);a,rest=p.parse_known_args()
 name='shellcrash-router-panel-'+a.device+'-'+VERSION
 base='https://github.com/'+REPOSITORY+'/releases/download/v'+VERSION
 with tempfile.TemporaryDirectory(prefix='sc-download-') as td:
  root=Path(td);package=fetch(base+'/'+name+'.tar.gz',MAX_PACKAGE)
  sums=fetch(base+'/SHA256SUMS',8192).decode()
  expected=[row.split()[0] for row in sums.splitlines() if len(row.split())==2 and row.split()[1]==name+'.tar.gz']
  if len(expected)!=1 or not re.fullmatch('[a-f0-9]{64}',expected[0]) or hashlib.sha256(package).hexdigest()!=expected[0]:raise ValueError('安装包校验失败，未执行安装')
  archive=root/'package.tar.gz';archive.write_bytes(package);path=extract(archive,root,name)
  return subprocess.run([sys.executable,str(path/'deploy.py'),*rest]).returncode
if __name__=='__main__':
 try:sys.exit(main())
 except Exception as e:print('未完成：'+str(e),file=sys.stderr);sys.exit(1)
