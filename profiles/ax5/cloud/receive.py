#!/usr/bin/python3
"""Forced SSH receiver. Backups never enter the HTTP document root."""
import os,sys,re,hashlib,tempfile
parts=os.environ.get('SSH_ORIGINAL_COMMAND','').split()
if len(parts)!=4 or parts[0]!='put': sys.exit(2)
_,kind,digest,ext=parts
if not re.fullmatch('[a-f0-9]{64}',digest): sys.exit(2)
allowed={'core':('tar.gz',18000000),'cn':('mrs',2000000),'backup':('tar.gz',3000000),'info':('txt',2048)}
if kind not in allowed or ext!=allowed[kind][0]: sys.exit(2)
base='/home/scmirror/ax5-backups' if kind=='backup' else '/etc/1panel/www/sites/shellcrash-core/ax5/objects'
fd,tmp=tempfile.mkstemp(prefix='.incoming-',dir=base)
try:
 h=hashlib.sha256();size=0
 with os.fdopen(fd,'wb') as out:
  while True:
   data=sys.stdin.buffer.read(65536)
   if not data: break
   size+=len(data)
   if size>allowed[kind][1]: raise ValueError('too large')
   h.update(data);out.write(data)
  out.flush();os.fsync(out.fileno())
 if not size or h.hexdigest()!=digest: raise ValueError('digest mismatch')
 if kind=='info':
  text=open(tmp).read()
  k=re.search(r'^KIND=(meta|singbox)$',text,re.M)
  v=re.search(r'^VERSION=(v?[0-9]+\.[0-9]+\.[0-9]+)$',text,re.M)
  h=re.search(r'^HASH=([a-f0-9]{64})$',text,re.M)
  if not k or not v or not h or not os.path.isfile(os.path.join(base,'core-'+h[1]+'.tar.gz')):raise ValueError('invalid core manifest')
 os.chmod(tmp,0o600 if kind=='backup' else 0o644)
 os.replace(tmp,os.path.join(base,kind+'-'+digest+'.'+ext))
 if kind=='info':
  fd2,pointer=tempfile.mkstemp(prefix='.meta-',dir=base)
  try:
   with os.fdopen(fd2,'wb') as out:
    out.write(open(os.path.join(base,kind+'-'+digest+'.'+ext),'rb').read());out.flush();os.fsync(out.fileno())
   os.chmod(pointer,0o644);os.replace(pointer,os.path.join(base,k[1]+'-info.txt'))
  finally:
   if os.path.exists(pointer):os.unlink(pointer)
 print(digest)
finally:
 if os.path.exists(tmp): os.unlink(tmp)
