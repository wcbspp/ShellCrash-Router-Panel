#!/usr/bin/env python3
"""Restricted SSH object store, no HTTP service required. Python 3.6+."""
import hashlib, json, os, re, sys, tempfile
from pathlib import Path

LIMITS = {'core':('tar.gz',18000000), 'dashboard':('tar.gz',2000000),
          'app':('tar.gz',4000000), 'backup':('tar.gz',25000000),
          'cn':(None,2000000), 'rules':('txt',262144), 'info':('txt',2048), 'probe':('txt',64)}

def transfer(root, private, command, source, output):
    root, private = Path(root), Path(private)
    if root.resolve() == private.resolve() or root.resolve() in private.resolve().parents:
        raise ValueError('private directory must be outside public tree')
    root.mkdir(parents=True, exist_ok=True)
    private.mkdir(parents=True, mode=0o700, exist_ok=True)
    if command == 'probe':
        for folder in (root, private):
            fd,p = tempfile.mkstemp(dir=str(folder));os.close(fd);os.unlink(p)
        output.write(b'SCMIRROR/2\n');return
    if command == 'catalog':
        rows=[]
        for p in sorted(private.glob('backup-*.tar.gz'), key=lambda p:p.stat().st_mtime, reverse=True)[:20]:
            if re.fullmatch(r'backup-[a-f0-9]{64}\.tar\.gz',p.name) and not p.is_symlink():
                rows.append({'sha256':p.name[7:71],'bytes':p.stat().st_size,'time':int(p.stat().st_mtime)})
        output.write(json.dumps({'backups':rows}).encode()+b'\n');return
    if command.startswith('manifest '):
        name=command.split()
        if len(name)!=2 or name[1] not in ('meta','singbox','core'):raise ValueError('invalid manifest request')
        p=root/(name[1]+'-info.txt')
        if p.is_symlink() or not p.is_file() or p.stat().st_size>2048:raise ValueError('manifest unavailable')
        output.write(p.read_bytes());return
    parts=command.split()
    if len(parts)==2 and parts[0] in ('core','cn','rules','info'):
        kind,digest=parts;action='put';ext='srs' if kind=='cn' else LIMITS[kind][0]
    elif len(parts)==4:
        action,kind,digest,ext=parts
    else: raise ValueError('invalid command')
    if action not in ('put','get','stat') or kind not in LIMITS or not re.fullmatch('[a-f0-9]{64}',digest): raise ValueError('invalid object')
    suffix,limit=LIMITS[kind]
    if ext != suffix and not(kind=='cn' and ext in ('mrs','srs')): raise ValueError('invalid extension')
    folder=private if kind=='backup' else root
    destination=folder/('{}-{}.{}'.format(kind,digest,ext))
    if action=='stat':
        if destination.is_symlink() or not destination.is_file() or destination.stat().st_size>limit:raise ValueError('object unavailable')
        h=hashlib.sha256()
        with destination.open('rb') as f:
            for chunk in iter(lambda:f.read(65536),b''):h.update(chunk)
        if h.hexdigest()!=digest:raise ValueError('stored object hash mismatch')
        output.write(digest.encode()+b'\n');return
    if action=='get':
        if destination.is_symlink() or not destination.is_file() or destination.stat().st_size>limit: raise ValueError('object unavailable')
        with destination.open('rb') as f:
            for chunk in iter(lambda:f.read(65536),b''): output.write(chunk)
        return
    fd,temp=tempfile.mkstemp(prefix='.incoming-',dir=str(folder))
    try:
        h=hashlib.sha256();size=0
        with os.fdopen(fd,'wb') as f:
            for chunk in iter(lambda:source.read(65536),b''):
                size+=len(chunk)
                if size>limit:raise ValueError('too large')
                h.update(chunk);f.write(chunk)
            f.flush();os.fsync(f.fileno())
        if not size or h.hexdigest()!=digest:raise ValueError('hash mismatch')
        pointer=None
        if kind=='info':
            text=Path(temp).read_text()
            k=re.search(r'^KIND=(meta|singbox)$',text,re.M)
            core=re.search(r'^(?:HASH|sha256)=([a-f0-9]{64})$',text,re.M)
            version=re.search(r'^(?:VERSION|version)=(v?[0-9]+\.[0-9]+\.[0-9]+)$',text,re.M)
            if not core or not version or not(root/('core-'+core[1]+'.tar.gz')).is_file():raise ValueError('invalid manifest')
            pointer=root/(k[1]+'-info.txt' if k else 'core-info.txt')
        os.chmod(temp,0o600 if kind=='backup' else 0o644);os.replace(temp,str(destination))
        if kind=='core':
            b=hashlib.sha1();b.update(('blob {}\0'.format(size)).encode())
            with destination.open('rb') as f:
                for chunk in iter(lambda:f.read(65536),b''):b.update(chunk)
            alias=root/('blob-'+b.hexdigest()+'.tar.gz')
            if not alias.exists():os.link(str(destination),str(alias))
        if pointer:
            fd,p=tempfile.mkstemp(prefix='.meta-',dir=str(root))
            try:
                with os.fdopen(fd,'wb') as f:f.write(destination.read_bytes());f.flush();os.fsync(f.fileno())
                os.chmod(p,0o644);os.replace(p,str(pointer))
            finally:
                if os.path.exists(p):os.unlink(p)
        if kind=='probe':
            for p in root.glob('probe-*.txt'):
                if p!=destination and re.fullmatch(r'probe-[a-f0-9]{64}\.txt',p.name) and not p.is_symlink():p.unlink()
        output.write(digest.encode()+b'\n')
    finally:
        if os.path.exists(temp):os.unlink(temp)

if __name__=='__main__':
    try:
        root=os.environ.get('SC_MIRROR_ROOT','/srv/shellcrash-mirror')
        private=os.environ.get('SC_BACKUP_ROOT',str(Path(root).parent/'shellcrash-private'))
        transfer(root,private,os.environ.get('SSH_ORIGINAL_COMMAND',''),sys.stdin.buffer,sys.stdout.buffer)
    except (ValueError,OSError) as error:
        print('remote object request rejected: '+str(error),file=sys.stderr);sys.exit(1)
