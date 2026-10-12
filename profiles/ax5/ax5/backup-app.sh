#!/bin/sh
set -eu
C=/data/ShellCrash
D=/tmp/ShellCrash
. "$C/ax5/remote.sh"
mode=${1:-local}
case "$mode" in local|remote) :;;*)exit 2;;esac
[ "$mode" != remote ] || remote_ready || { echo '请先开启并验证远程仓库';exit 2; }
# Budget the temporary copy and compressed archive before allocating tmpfs.
available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
staging=0
for path in "$C/configs" "$C/ui" "$C/ax5" "$C/ruleset" "$C/cache/targets" /data/ShellCrash-tool;do
 if [ -e "$path" ];then bytes=$(du -sk "$path" | awk '{print $1}');staging=$((staging+bytes));fi
done
compressed=$staging;[ "$compressed" -le 4000 ] || compressed=4000
[ "${available:-0}" -ge "$((staging+compressed+12288))" ] || { echo '可用内存不足以安全打包，现有服务保持运行';exit 1; }
umask 077
mkdir -p "$D"
stage="$D/backup-stage"
file="$D/application-backup.tar.gz"
trap 'rm -rf "$stage";rm -f "$file.new"' EXIT
rm -rf "$stage";mkdir -p "$stage"
# Only project files, never firmware, Entware, ZeroTier identity, SSH keys or runtime logs.
for folder in configs ui ax5 ruleset;do
 [ ! -d "$C/$folder" ] || cp -R "$C/$folder" "$stage/"
done
for name in webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified;do rm -f "$stage/configs/$name";done
[ ! -d "$C/cache/targets" ] || { mkdir -p "$stage/cache";cp -R "$C/cache/targets" "$stage/cache/"; }
cp -R /data/ShellCrash-tool "$stage/ShellCrash-tool"
rm -f "$stage/ShellCrash-tool/configs/command.env"
. "$C/ax5/core-env.sh"
hash=$HASH;version=$VERSION
mkdir -p "$stage/cache";cp "$C/cache/core.env" "$stage/cache/core.env"
printf 'format=1\nmodel=AX5\ncore_sha256=%s\ncore_version=%s\ncore_archive=core-%s.tar.gz\ncreated=%s\n' "$hash" "$version" "$hash" "$(date +%s)" > "$stage/backup.info"
cat > "$stage/RESTORE.txt" <<'RESTORE'
ShellCrash panel application backup / format 1
Model: AX5 / architecture: armv7
Archive format: gzip compressed tar (.tar.gz), NOT firmware.
Extract on a computer into an empty temporary directory first. Do not extract over a running router.
Inspect backup.info. Obtain core-<core_sha256>.tar.gz separately and verify SHA256.
Layout: AX5: configs/ui/ax5/ruleset/cache => /data/ShellCrash; ShellCrash-tool => /data/ShellCrash-tool
This archive includes private subscription/node credentials. Keep it private.
Excluded: firmware, Entware, ZeroTier identity, WebDAV credentials, SSH keys, runtime logs.
Restore only to the same model/architecture with local LAN recovery access.
Keep the current project and working core before changing files. Stop the proxy, restore project files,
and reinstall its management/boot integration using the matching project installer.
Check the candidate configuration using the target core before starting. Restore the old files if validation fails.
RAM/small-flash operation is unchanged. Configure and verify WebDAV credentials again.
Verify LAN, nodes, rules, DNS, one watchdog, autostart, and ZeroTier after restoration.
No automatic browser import is available in this version.
RESTORE
tar -czf "$file.new" -C "$stage" .
[ "$(wc -c < "$file.new")" -le 4000000 ] || { rm -f "$file.new";echo '备份超出轻量限制';exit 1; }
mv "$file.new" "$file"
if [ "$mode" = remote ];then
 if ! remote_has core "$hash" tar.gz;then
  archive="$C/cache/core-armv7.tar.gz"
  "$C/ax5/verify-core.sh"
  remote_put core "$archive" tar.gz >/dev/null
 fi
 remote_put info "$C/cache/core.env" txt >/dev/null
 remote_put backup "$file" tar.gz > "$D/backup-sha"
 date +%s > "$C/configs/backup-time"
 rm -f "$C/configs/backup-pending"
fi
echo '应用备份完成；内核按校验值单独存储'
