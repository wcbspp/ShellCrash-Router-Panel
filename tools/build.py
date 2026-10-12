#!/usr/bin/env python3
"""Build one device package from common source; never run on a router."""
import argparse,hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROFILES=('ax5','k2p')
def render(text,profile):
 out=[];condition=None;active=True
 for line in text.splitlines(keepends=True):
  stripped=line.rstrip('\r\n')
  if stripped.startswith('@@if ') and stripped.endswith('@@'):
   if condition is not None:raise ValueError('Nested profile block')
   condition=stripped[5:-2]
   if condition not in PROFILES:raise ValueError('Unknown profile')
   active=condition==profile
  elif stripped=='@@else@@':
   if condition is None:raise ValueError('Else without profile')
   active=condition!=profile
  elif stripped=='@@end@@':
   if condition is None:raise ValueError('End without profile')
   condition=None;active=True
  elif active:out.append(line)
 if condition is not None:raise ValueError('Unclosed profile block')
 return ''.join(out)
def build(profile,output=None):
 target=Path(output) if output else ROOT/'build'/profile
 target.mkdir(parents=True,exist_ok=True)
 manifest=json.loads((ROOT/'profiles'/profile/'manifest.json').read_text())
 for relative,source in manifest.items():
  for name in (relative,source):
   if Path(name).is_absolute() or '..' in Path(name).parts:raise ValueError('Unsafe build path')
  src=ROOT/source;dst=target/relative;dst.parent.mkdir(parents=True,exist_ok=True)
  if src.suffix=='.in':dst.write_text(render(src.read_text(),profile));dst.chmod(0o644)
  else:shutil.copy2(src,dst)
 for name in ['README.md','LICENSE','NOTICE.md','VERSION','deploy.py','update.py']:
  shutil.copy2(ROOT/name,target/name)
 # The firmware-specific scripts keep their legacy paths; no compiler runs on-device.
 shutil.copy2(ROOT/'install.sh',target/'setup.sh')
 shutil.copy2(ROOT/'tools/verify_package.py',target/'tools/verify_package.py')
 shutil.copytree(ROOT/'docs',target/'docs',dirs_exist_ok=True)
 (target/'DEVICE').write_text(profile+'\n')
 files=sorted(p for p in target.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc' and p.name!='MANIFEST.sha256')
 (target/'MANIFEST.sha256').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(target)}\n' for p in files))
 return target
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('profile',choices=(*PROFILES,'all'));p.add_argument('--output',type=Path);a=p.parse_args()
 if a.output and a.profile=='all':p.error('--output requires one device')
 for profile in PROFILES if a.profile=='all' else [a.profile]:print(build(profile,a.output))
