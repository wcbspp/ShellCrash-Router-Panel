#!/usr/bin/env python3
"""Verify every package file before deployment, including unexpected files."""
import hashlib,re,sys
from pathlib import Path

def verify(root,extra_inputs=()):
 entries={}
 for row in (root/'MANIFEST.sha256').read_text().splitlines():
  m=re.fullmatch(r'([a-f0-9]{64})  (.+)',row)
  if not m:raise ValueError('校验清单格式错误')
  sha,name=m.groups();p=Path(name)
  if p.is_absolute() or '..' in p.parts or name in entries:raise ValueError('校验路径错误')
  entries[name]=sha
 actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p.name!='MANIFEST.sha256' and '__pycache__' not in p.parts and p.suffix!='.pyc'}
 allowed=set()
 for supplied in extra_inputs:
  if supplied is None:continue
  try:name=str(Path(supplied).resolve().relative_to(root.resolve()))
  except ValueError:continue
  if name not in entries:allowed.add(name)
 if actual-allowed!=set(entries):raise ValueError('安装包缺文件或含额外文件')
 for name,sha in entries.items():
  p=root/name
  if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:raise ValueError('文件校验失败：'+name)
 print('安装包文件校验通过')
if __name__=='__main__':
 try:verify(Path(sys.argv[1]).resolve())
 except (ValueError,OSError,IndexError) as e:print(e,file=sys.stderr);sys.exit(1)
