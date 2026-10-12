#!/usr/bin/env python3
"""Prepare installation files and a verified fixed-version core on a networked PC."""
import argparse,hashlib,json,shutil,tarfile,urllib.request
from pathlib import Path
from build import build,ROOT
CORES={
 'ax5':{'url':'https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@21734eca91ec7a540494a5f43eac485403c18dac/bin/singbox/singbox-linux-armv7.tar.gz','fallback':'https://raw.githubusercontent.com/juewuy/ShellCrash/21734eca91ec7a540494a5f43eac485403c18dac/bin/singbox/singbox-linux-armv7.tar.gz','sha256':'40d97dc43df35d326916d488f748371e2e773a59569c01e23330081274ebf65b','limit':12000000},
}
def core_spec(profile):
 if profile=='ax5':return CORES[profile]
 values=dict(row.split('=',1) for row in (ROOT/'profiles/k2p/examples/core-installed.info').read_text().splitlines() if '=' in row)
 return {'url':values['fallback1'],'fallback':values['fallback2'],'sha256':values['sha256'],'limit':int(values['archive_size'])}
def validate_archive(path):
 with tarfile.open(path,'r:gz') as t:
  members=t.getmembers();found=False
  if len(members)>50 or sum(m.size for m in members)>40000000:raise ValueError('内核归档大小异常')
  for m in members:
   p=Path(m.name)
   if p.is_absolute() or '..' in p.parts or not(m.isfile() or m.isdir()):raise ValueError('内核归档路径异常')
   if m.isfile() and m.name=='CrashCore':found=True
  if not found:raise ValueError('内核归档缺少 CrashCore')
def prepare(profile,local_core=None):
 output=ROOT/'dist'/('offline-'+profile)
 if output.exists():raise ValueError('离线目录已存在，请换名保存旧包后再准备')
 spec=core_spec(profile);temporary=ROOT/'dist'/('core-'+profile+'.pending')
 temporary.parent.mkdir(exist_ok=True)
 try:
  if local_core:shutil.copyfile(local_core,temporary)
  else:
   for url in (spec['url'],spec['fallback']):
    try:
     with urllib.request.urlopen(url,timeout=120) as r,temporary.open('wb') as f:
      size=0
      while True:
       chunk=r.read(65536)
       if not chunk:break
       size+=len(chunk)
       if size>spec['limit']:raise ValueError('内核下载超过限额')
       f.write(chunk)
     if hashlib.sha256(temporary.read_bytes()).hexdigest()!=spec['sha256']:raise ValueError('内核 SHA256 不匹配')
     break
    except Exception:
     temporary.unlink(missing_ok=True)
   else:raise ValueError('内核下载失败；可用 --core-file 指定此前下载的同版本包')
  if temporary.stat().st_size>spec['limit'] or hashlib.sha256(temporary.read_bytes()).hexdigest()!=spec['sha256']:raise ValueError('离线内核不符合固定版本校验')
  validate_archive(temporary)
  build(profile,output);shutil.move(temporary,output/'core-offline.tar.gz')
  files=sorted(p for p in output.rglob('*') if p.is_file() and p.name!='MANIFEST.sha256' and '__pycache__' not in p.parts and p.suffix!='.pyc')
  (output/'MANIFEST.sha256').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(output)}\n' for p in files))
  print('已准备：'+str(output));return output
 finally:temporary.unlink(missing_ok=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('profile',choices=['ax5','k2p']);p.add_argument('--core-file',type=Path);a=p.parse_args()
 try:prepare(a.profile,a.core_file)
 except (ValueError,OSError) as e:p.exit(1,str(e)+'\n')
