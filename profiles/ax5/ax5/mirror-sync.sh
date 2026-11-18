#!/bin/sh
set -eu
. /data/ShellCrash/ax5/core-env.sh
"$C/ax5/verify-core.sh"
"$C/ax5/mirror-upload.sh" core "$C/cache/core-armv7.tar.gz" tar.gz >/dev/null
"$C/ax5/mirror-upload.sh" info "$C/cache/core.env" txt >/dev/null
if [ "$KIND" = meta ];then ext=mrs;else ext=srs;fi
"$C/ax5/mirror-upload.sh" cn "$C/ruleset/cn.$ext" "$ext" >/dev/null
if [ "$(remote_transport)" = webdav ];then
 for name in Country.mmdb GeoSite.dat;do
  [ ! -s "$C/ruleset/native/$name" ] || "$C/ax5/mirror-upload.sh" rules "$C/ruleset/native/$name" "${name##*.}" >/dev/null
 done
fi
rm -f "$C/configs/mirror-pending"
"$C/ax5/backup-config.sh"
"$C/ax5/mirror-status.sh" "$KIND"
