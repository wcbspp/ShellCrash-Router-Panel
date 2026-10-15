#!/bin/sh
set -eu
C=/data/ShellCrash
D=/tmp/ShellCrash
. "$C/ax5/remote.sh"
rm -f "$D/backup-error"
mode=${1:-local}
case "$mode" in local|remote) :;;*)exit 2;;esac
[ "$mode" != remote ] || remote_transfer_ready || { echo '请先开启、验证并连接远程仓库';exit 2; }
# Hard-link snapshot on the same flash filesystem; only metadata is staged.
# The archive is streamed into a bounded RAM output, preserving the old file on failure.
available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
protect=$(lua -e "print(dofile('$C/ax5/common.lua').limits().protect_mb)")
case "$protect" in ''|*[!0-9]*) echo '无法读取内存保护设置，未创建备份';exit 1;;esac
[ "$protect" -ge 12 ] && [ "$protect" -le 64 ] || { echo '内存保护设置无效，未创建备份';exit 1; }
protect_kb=$((protect*1024))
required=$((protect_kb+512))
if [ "${available:-0}" -lt "$required" ];then
 mkdir -p "$D"
 printf '应用备份暂缓：可用 %s KB，安全打包至少需要 %s KB；当前服务保持运行\n' "${available:-0}" "$required" > "$D/backup-error"
 cat "$D/backup-error";exit 1
fi
flash=$(df -Pk "$C" | awk 'END{print $4}')
[ "${flash:-0}" -ge 256 ] || { echo '应用备份暂缓：Flash 余量不足 256 KB，未创建快照';exit 1; }
umask 077
mkdir -p "$D"
stage="$C/.backup-stage.$$"
file="$D/application-backup.tar.gz"
trap 'rm -rf "$stage";rm -f "$file.new" "$D/runtime-assets-backup.tar.gz" "$D/runtime-assets-backup.tar.gz.new" "$D/runtime-backup.info" "$D/runtime-tar.error"' EXIT
rm -rf "$stage";mkdir -p "$stage"
# Only project files, never firmware, Entware, ZeroTier identity, SSH keys or runtime logs.
for folder in configs ui ax5 ruleset;do
 [ ! -d "$C/$folder" ] || cp -al "$C/$folder" "$stage/"
done
for name in webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified;do rm -f "$stage/configs/$name";done
[ ! -d "$C/cache/targets" ] || { mkdir -p "$stage/cache";cp -al "$C/cache/targets" "$stage/cache/"; }
cp -al /data/ShellCrash-tool "$stage/ShellCrash-tool"
rm -f "$stage/ShellCrash-tool/configs/command.env"
sh "$C/ax5/backup-links.sh" "$stage" ax5
. "$C/ax5/core-env.sh"
hash=$HASH;version=$VERSION
mkdir -p "$stage/cache";cp "$C/cache/core.env" "$stage/cache/core.env"
panel_version=$(cat "$C/ax5/panel-version" 2>/dev/null || printf unknown)
printf 'format=1\nmodel=AX5\npanel_version=%s\ncore_sha256=%s\ncore_version=%s\ncore_archive=core-%s.tar.gz\ncreated=%s\n' "$panel_version" "$hash" "$version" "$hash" "$(date +%s)" > "$stage/backup.info"
cat > "$stage/RESTORE.txt" <<'RESTORE'
ShellCrash panel application backup / format 1
Model: AX5 / architecture: armv7
Archive format: gzip compressed tar (.tar.gz), NOT firmware.
Extract on a computer into an empty temporary directory first. Do not extract over a running router.
Inspect backup.info. Obtain core-<core_sha256>.tar.gz separately and verify SHA256.
Layout: AX5: configs/ui/ax5/ruleset/cache => /data/ShellCrash; ShellCrash-tool => /data/ShellCrash-tool
This archive includes private subscription/node credentials. Keep it private.
Excluded: firmware, Entware, ZeroTier identity, WebDAV credentials, SSH keys, runtime logs and generated runtime links.
Runtime JSON/config aliases are rebuilt by the matching installer and start hooks.
Restore only to the same model/architecture with local LAN recovery access.
Keep the current project and working core before changing files. Stop the proxy, restore project files,
and reinstall its management/boot integration using the matching project installer.
Check the candidate configuration using the target core before starting. Restore the old files if validation fails.
RAM/small-flash operation is unchanged. Configure and verify WebDAV credentials again.
Verify LAN, nodes, rules, DNS, one watchdog, autostart, and ZeroTier after restoration.
No automatic browser import is available in this version.
RESTORE
sh "$C/ax5/backup-guide.sh" "$stage" AX5 application
available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
limit=$(( (available-protect_kb-256)*1024 ));[ "$limit" -le 4000000 ] || limit=4000000
[ "$limit" -ge 32768 ] || { echo '打包期间可用内存不足，当前服务保持运行';exit 1; }
: > "$D/backup-tar.error"
tar -cf - -C "$stage" . 2> "$D/backup-tar.error" | gzip -c | head -c "$((limit+1))" > "$file.new"
[ "$(wc -c < "$file.new")" -le "$limit" ] && [ ! -s "$D/backup-tar.error" ] || { echo '备份超过安全内存预算或打包失败，未替换旧备份';exit 1; }
gzip -t "$file.new" || { echo '备份压缩校验失败';exit 1; }
mv "$file.new" "$file"
rm -rf "$stage"
if [ "$mode" = remote ];then
 if ! remote_has core "$hash" tar.gz;then
  archive="$C/cache/core-armv7.tar.gz"
  "$C/ax5/verify-core.sh"
  remote_put core "$archive" tar.gz >/dev/null
 fi
 remote_put info "$C/cache/core.env" txt >/dev/null
 if [ "$(remote_transport)" = webdav ];then
  . "$C/ax5/backup-set.sh"
  backup_set_publish "$file"
 else remote_put backup "$file" tar.gz > "$D/backup-sha";fi
 date +%s > "$C/configs/backup-time"
 rm -f "$C/configs/backup-pending"
fi
if [ "$mode" = remote ];then echo '完整备份已保存：应用、内核及已安装运行资源；当前设置保持不变'
else echo '应用与配置已导出；内核和临时运行资源需另行保存';fi
