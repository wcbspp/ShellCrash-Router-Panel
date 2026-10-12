#!/usr/bin/env python3
"""Generate the two device release archives; public release is a separate gate."""
import gzip,hashlib,io,tarfile,json
from pathlib import Path
from build import build,ROOT,PROFILES
version=(ROOT/'VERSION').read_text().strip();dist=ROOT/'dist';dist.mkdir(exist_ok=True)
for profile in PROFILES:
 src=build(profile);name='shellcrash-router-panel-'+profile+'-'+version
 dest=dist/(name+'.tar.gz')
 with dest.open('wb') as raw,gzip.GzipFile(fileobj=raw,mode='wb',mtime=0) as gz,tarfile.open(fileobj=gz,mode='w') as t:
  for p in sorted(src.rglob('*')):
   if not p.is_file() or '__pycache__' in p.parts or p.suffix=='.pyc':continue
   if p.is_symlink():raise ValueError('Symlink in package')
   data=p.read_bytes();i=tarfile.TarInfo(name+'/'+str(p.relative_to(src)));i.size=len(data);i.mode=0o755 if p.suffix=='.sh' else 0o644;t.addfile(i,io.BytesIO(data))
 print(dest)
(dist/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(dist.glob('shellcrash-router-panel-*-'+version+'.tar.gz'))))
