#!/bin/sh
set -eu
C=/data/ShellCrash
R=/tmp/ShellCrash
D=$R
. "$C/ax5/remote.sh"
remote_ready || exit 0
if [ "${SC_BACKUP_WORKER:-0}" != 1 ];then
 SC_BACKUP_WORKER=1 "$C/ax5/backup-config.sh" </dev/null >> "$R/backup.log" 2>&1 &
 exit 0
fi
mkdir "$R/config-backup.lock" 2>/dev/null || exit 0
umask 077
file="$R/config-backup.tar.gz"
trap 'rm -f "$file"; rmdir "$R/config-backup.lock"' EXIT
# Private receiver path only; no configuration or identity is published over HTTP.
mkdir -p "$C/cache/targets"
tar -czf "$file" -C "$C" --exclude=webdav.auth --exclude=webdav.user --exclude=mirror-id --exclude=mirror_key --exclude=mirror_known_hosts --exclude=remote.verified configs ruleset cache/core.env cache/core.sha256 cache/targets
if "$C/ax5/mirror-upload.sh" backup "$file" tar.gz > "$R/backup-sha"; then
 date +%s > "$C/configs/backup-time"
 rm -f "$C/configs/backup-pending"
else
 date +%s > "$C/configs/backup-pending"
 exit 1
fi
