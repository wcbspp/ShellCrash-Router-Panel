#!/bin/sh
set -eu
. /data/ShellCrash/ax5/core-env.sh
"$C/ax5/verify-core.sh"
"$C/ax5/mirror-upload.sh" core "$C/cache/core-armv7.tar.gz" tar.gz >/dev/null
"$C/ax5/mirror-upload.sh" info "$C/cache/core.env" txt >/dev/null
[ "$KIND" != meta ] || "$C/ax5/mirror-upload.sh" cn "$C/ruleset/cn.mrs" mrs >/dev/null
rm -f "$C/configs/mirror-pending"
"$C/ax5/backup-config.sh"
"$C/ax5/mirror-status.sh" "$KIND"
