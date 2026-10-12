#!/bin/sh
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
CRASHDIR=$C
mkdir -p /tmp/ShellCrash
 . "$C/starts/core_release.sh"
 release="$C/configs/core-installed.info"
 release_valid "$release" || { logger -t ShellCrash 'Installed core metadata invalid; refusing download'; exit 1; }
 # An optional external persistent cache is verified against the installed manifest.
 local_archive=$(sed -n 's/^archive=//p' "$C/configs/core-cache.conf" 2>/dev/null | head -1)
 if [ -n "$local_archive" ] && printf '%s' "$local_archive" | grep -Eq '^/[A-Za-z0-9/._-]+$' && ! printf '%s' "$local_archive" | grep -q '\.\.' && [ -s "$local_archive" ];then
  if printf '%s  %s\n' "$(release_get sha256 "$release")" "$local_archive" | sha256sum -c - >/dev/null 2>&1;then cp "$local_archive" /tmp/ShellCrash/CrashCore.tar.gz;fi
 fi
 if [ -s /tmp/ShellCrash/CrashCore.tar.gz ]; then
  printf '%s  %s\n' "$(release_get sha256 "$release")" /tmp/ShellCrash/CrashCore.tar.gz | sha256sum -c - >/dev/null 2>&1 && exit 0
  rm -f /tmp/ShellCrash/CrashCore.tar.gz
 fi
if [ ! -s /tmp/ShellCrash/CrashCore.tar.gz ]; then
 downloaded=0
 . "$C/starts/mirror_lib.sh"
 expected=$(release_get sha256 "$release")
 if remote_fetch core "$expected" tar.gz /tmp/ShellCrash/core-download.tgz "$(release_get archive_size "$release")";then downloaded=1;fi
 extra_urls='';[ "$(remote_transport)" != webdav ] && remote_ready && extra_urls=$(sed '/^#/d; /^$/d' "$C/configs/core_mirrors.list")
 for u in $(mirror_core_url "$release") $extra_urls; do
  [ "$downloaded" = 1 ] && break
  installed=$(release_get version "$release")
  u=$(printf '%s' "$u" | sed "s/singbox-mini-[0-9][0-9.]*-mipsle/singbox-mini-$installed-mipsle/")
  # Preserve the user-configured mirror priority; never accept a different program.
  if curl -4 --noproxy '*' -fsSL --connect-timeout 8 --max-time 90 --max-filesize "$(release_get archive_size "$release")" "$u" -o /tmp/ShellCrash/core-download.tgz && printf '%s  %s\n' "$expected" /tmp/ShellCrash/core-download.tgz | sha256sum -c - >/dev/null 2>&1; then downloaded=1; break; fi
  rm -f /tmp/ShellCrash/core-download.tgz
 done
 SC_REMOTE_TRIED=1
 if [ "$downloaded" = 1 ] || release_download "$release" /tmp/ShellCrash/core-download.tgz; then
  mv /tmp/ShellCrash/core-download.tgz /tmp/ShellCrash/CrashCore.tar.gz
  logger -t ShellCrash 'Core downloaded and verified; configured mirrors first, public fallback'
 else
  rm -f /tmp/ShellCrash/core-download.tgz
  logger -t ShellCrash 'Core download failed; ordinary routing remains available'
  exit 1
 fi
fi
