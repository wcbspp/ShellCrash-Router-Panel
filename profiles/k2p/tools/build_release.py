#!/usr/bin/env python3
"""Package only the public source allowlist; exclude runtime configuration."""
import hashlib,json,shutil,tarfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
version=(ROOT/'VERSION').read_text().strip()
name=f'padavan-shellcrash-panel-{version}'
dist=ROOT/'dist';dist.mkdir(exist_ok=True)
files=[]
for entry in ['README.md','CHANGELOG.md','NOTICE.md','LICENSE','VERSION','install.sh','uninstall.sh','backup.sh','restore_storage.sh','vendor','payload','examples','docs','tools','tests']:
 p=ROOT/entry
 files += [p] if p.is_file() else [f for f in p.rglob('*') if f.is_file() and '__pycache__' not in f.parts]
files=sorted(files)
for f in files:
 if f.is_symlink() or f.stat().st_size>1024*1024:raise SystemExit('Unexpected artifact: '+str(f.relative_to(ROOT)))
manifest=''.join(f'{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(ROOT)}\n' for f in files)
def clean_metadata(info):
 info.uid=info.gid=0;info.uname=info.gname='';return info
with tarfile.open(dist/(name+'.tar.gz'),'w:gz') as archive:
 for f in files:archive.add(f,arcname=name+'/'+str(f.relative_to(ROOT)),recursive=False,filter=clean_metadata)
 import io
 b=manifest.encode();info=tarfile.TarInfo(name+'/MANIFEST.sha256');info.size=len(b);info.mode=0o644;archive.addfile(info,io.BytesIO(b))
with zipfile.ZipFile(dist/(name+'.zip'),'w',compression=zipfile.ZIP_DEFLATED) as archive:
 for f in files:archive.write(f,name+'/'+str(f.relative_to(ROOT)))
 archive.writestr(name+'/MANIFEST.sha256',manifest)
upstream=ROOT/'vendor/ShellCrash-1.9.4.tar.gz'
metadata=json.loads((ROOT/'vendor/UPSTREAM.json').read_text())
if hashlib.sha256(upstream.read_bytes()).hexdigest()!=metadata['archive_sha256']:raise SystemExit('Upstream archive hash mismatch')
shutil.copyfile(upstream,dist/upstream.name)
assets=[dist/(name+'.tar.gz'),dist/(name+'.zip'),dist/upstream.name]
(dist/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in assets))
print('\n'.join(str(p) for p in assets))
