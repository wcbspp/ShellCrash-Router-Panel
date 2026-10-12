#!/usr/bin/env python3
"""Package only public source; no runtime files or firmware."""
import hashlib, io, tarfile, zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
version=(root/'VERSION').read_text().strip()
name='XiaoMiAX5-shellcrash-panel-'+version
dist=root/'dist';dist.mkdir(exist_ok=True)
files=[]
for entry in ['README.md','install.sh','bootstrap.sh','vendor','examples','VERSION','CHANGELOG.md','LICENSE','NOTICE','ax5','ui','zerotier','cloud','docs','tool-patches','tests','tools']:
 p=root/entry
 files += [p] if p.is_file() else [f for f in p.rglob('*') if f.is_file() and '__pycache__' not in f.parts and f.suffix!='.pyc']
files=sorted(files)
for p in files:
 if p.is_symlink() or p.stat().st_size>1024*1024:raise SystemExit('Unexpected file: '+str(p.relative_to(root)))
manifest=''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n' for p in files)
def metadata(i):
 i.uid=i.gid=0;i.uname=i.gname='';return i
with tarfile.open(dist/(name+'.tar.gz'),'w:gz')as t:
 for p in files:t.add(p,arcname=name+'/'+str(p.relative_to(root)),recursive=False,filter=metadata)
 data=manifest.encode();info=tarfile.TarInfo(name+'/MANIFEST.sha256');info.size=len(data);t.addfile(info,io.BytesIO(data))
with zipfile.ZipFile(dist/(name+'.zip'),'w',compression=zipfile.ZIP_DEFLATED)as z:
 for p in files:z.write(p,name+'/'+str(p.relative_to(root)))
 z.writestr(name+'/MANIFEST.sha256',manifest)
(dist/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(dist.glob(name+'.*'))))
print(name)
