#!/bin/sh
# ShellCrashLegacyStorageGuard: restore small RAM overlays at each boot.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
D=/tmp/sc-legacy-guard
umask 077
mkdir -p "$D"
wrap(){
 target=$1; kind=$2; name=${target##*/}
 grep -q 'ShellCrashLegacyStorageGuard' "$target" && return 0
 cp "$target" "$D/$name.original" || return 1
 chmod 700 "$D/$name.original"
 {
  echo '#!/bin/sh'
  echo '# ShellCrashLegacyStorageGuard'
  echo 'export PATH=/usr/sbin:/usr/bin:/sbin:/bin'
  if [ "$kind" = storage ]; then
   echo '[ "$1" != save ] || exec /etc/storage/ShellCrash/starts/save_storage.sh'
  else
   echo 'if [ "$(/usr/sbin/nvram get ss_enable)" != 1 ]; then'
   echo ' logger -t ShellCrash "Legacy SSR rule update skipped: SSR is disabled"'
   echo ' exit 0'
   echo 'fi'
  fi
  printf 'exec %s "$@"\n' "$D/$name.original"
 } > "$D/$name.wrapper"
 chmod 700 "$D/$name.wrapper"
 mount -o bind "$D/$name.wrapper" "$target"
}
wrap /sbin/mtd_storage.sh storage || exit 1
wrap /usr/bin/update_chnroute.sh rules || exit 1
wrap /usr/bin/update_gfwlist.sh rules || exit 1
