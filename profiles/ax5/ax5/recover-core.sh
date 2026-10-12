#!/bin/sh
set -eu
. /data/ShellCrash/ax5/core-env.sh
mkdir -p "$R"
# A partially committed switch keeps the previous manifest. Hash checks determine recovery.
# The installed manifest stays authoritative: never fetch an implicit newer core at boot.
public_urls="$SOURCE"
case "$SOURCE" in https://raw.githubusercontent.com/juewuy/ShellCrash/*) public_urls="$(printf '%s' "$SOURCE" | sed 's#https://raw.githubusercontent.com/juewuy/ShellCrash/#https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@#') $SOURCE";; esac
mirror_url='';[ -z "$MIRROR" ] || mirror_url="$MIRROR/core-$HASH.tar.gz"
if remote_fetch core "$HASH" tar.gz "$R/recovered.tar.gz" 18000000;then
 tar -tzf "$R/recovered.tar.gz" | grep -qx CrashCore && { mv "$R/recovered.tar.gz" "$C/cache/core-armv7.tar.gz";exit 0; }
 rm -f "$R/recovered.tar.gz"
fi
for url in $mirror_url $public_urls; do
 if curl -4 --noproxy '*' -fsSL --connect-timeout 8 --max-time 60 --max-filesize 18000000 "$url" -o "$R/recovered.tar.gz"; then
  actual=$(openssl dgst -sha256 "$R/recovered.tar.gz" | awk '{print $NF}')
  if [ "$actual" = "$HASH" ]; then
   tar -tzf "$R/recovered.tar.gz" | grep -qx CrashCore || continue
   rm -f "$C/cache/core-armv7.tar.gz"
   mv "$R/recovered.tar.gz" "$C/cache/core-armv7.tar.gz"
   exit 0
  fi
 fi
 rm -f "$R/recovered.tar.gz"
done
echo 'No verified core archive available; configuration was not modified.' >&2
exit 1
