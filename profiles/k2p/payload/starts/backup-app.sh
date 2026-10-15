#!/bin/sh
set -eu
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
. "$C/starts/remote.sh"
mode=${1:-local}
case "$mode" in local|remote) :;;*)exit 2;;esac
[ "$mode" != remote ] || remote_transfer_ready || { echo '请先开启、验证并连接远程仓库';exit 2; }
# Metadata-only snapshot on the same Storage filesystem: hard links do not
# duplicate the project files in RAM. The hidden root is excluded by the
# installed Storage saver; its lock prevents a concurrent commit while built.
available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
. "$C/starts/resource_health.sh"
resource_limits
[ "$rh_limits_valid" = 1 ] || { echo '内存保护设置无效，未创建备份';exit 1; }
protect_kb=$((rh_protect_mb*1024))
[ "${available:-0}" -ge "$((protect_kb+512))" ] || { echo '可用内存不足以安全打包，现有服务保持运行';exit 1; }
mkdir /tmp/shellcrash-storage-save.lock 2>/dev/null || { echo 'Storage 正在保存，请稍后重试';exit 1; }
lockheld=1
umask 077
mkdir -p "$D"
stage="/etc/storage/.sc-backup-stage.$$"
file="$D/application-backup.tar.gz"
trap 'rm -rf "$stage";rm -f "$file.new" "$D/backup-download.txt.new" "$D/runtime-assets-backup.tar.gz" "$D/runtime-assets-backup.tar.gz.new" "$D/runtime-backup.info" "$D/runtime-tar.error";[ "$lockheld" != 1 ] || rmdir /tmp/shellcrash-storage-save.lock 2>/dev/null' EXIT
rm -rf "$stage";mkdir -p "$stage"
# Only project files, never firmware, Entware, ZeroTier identity, SSH keys or runtime logs.
for folder in configs ui padavan starts libs tools menus task jsons yamls ruleset;do
 [ ! -d "$C/$folder" ] || cp -al "$C/$folder" "$stage/"
done
for name in recovery-enabled webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified;do rm -f "$stage/configs/$name";done
for name in start.sh menu.sh init.sh version task_en.list task.list singbox_providers.list servers.list clash_providers.list fallback_filter.list fake_ip_filter.list cn_ipv6.txt;do [ ! -f "$C/$name" ] || cp -al "$C/$name" "$stage/";done
sh "$C/starts/backup-links.sh" "$stage" k2p
hash=$(sed -n 's/^sha256=//p' "$C/configs/core-installed.info");version=$(sed -n 's/^version=//p' "$C/configs/core-installed.info")
panel_version=$(cat "$C/starts/panel-version" 2>/dev/null || printf unknown)
autostart=1;[ ! -f "$C/.dis_startup" ] || autostart=0
enabled=1;[ ! -f "$C/configs/panel-disabled" ] || enabled=0
traffic_mode=$(cat /tmp/ShellCrash/traffic-mode 2>/dev/null || :)
case "$traffic_mode" in rule|direct|global) :;;*)traffic_mode=rule;;esac
printf 'format=1\nmodel=K2P\npanel_version=%s\ncore_sha256=%s\ncore_version=%s\ncore_archive=core-%s.tar.gz\ncreated=%s\nautostart=%s\nenabled=%s\ntraffic_mode=%s\n' "$panel_version" "$hash" "$version" "$hash" "$(date +%s)" "$autostart" "$enabled" "$traffic_mode" > "$stage/backup.info"
cat > "$stage/RESTORE.txt" <<'RESTORE'
ShellCrash panel application backup / format 1
Model: K2P / architecture: mipsle
Archive format: gzip compressed tar (.tar.gz), NOT firmware.
Extract on a computer into an empty temporary directory first. Do not extract over a running router.
Inspect backup.info. Obtain core-<core_sha256>.tar.gz separately and verify SHA256.
Layout: K2P: configs/ui/padavan/starts/libs/tools/menus/task/jsons/yamls/ruleset and native root scripts/provider/task lists => /etc/storage/ShellCrash
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
sh "$C/starts/backup-guide.sh" "$stage" K2P application
# Reserve real remaining RAM instead of assuming the compressed archive is
# as large as the uncompressed project. Bound the output while it is written.
available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
limit=$(( (available-protect_kb-256)*1024 ));[ "$limit" -le 4000000 ] || limit=4000000
[ "$limit" -ge 32768 ] || { echo '打包期间可用内存不足，当前服务保持运行';exit 1; }
: > "$D/backup-tar.error"
tar -cf - -C "$stage" . 2> "$D/backup-tar.error" | gzip -c | head -c "$((limit+1))" > "$file.new"
[ "$(wc -c < "$file.new")" -le "$limit" ] && [ ! -s "$D/backup-tar.error" ] || { echo '备份超过安全内存预算或打包失败，未替换旧备份';exit 1; }
gzip -t "$file.new" || { echo '备份压缩校验失败';exit 1; }
mv "$file.new" "$file"
rm -rf "$stage"
rmdir /tmp/shellcrash-storage-save.lock;lockheld=0
if [ "$mode" = local ];then
 # Release the file copy before allocating the encoded download representation.
 rm -rf "$stage"
 available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
 size=$(wc -c < "$file" | tr -d "[:space:]");required=$(( (size*4/3+1023)/1024+protect_kb ))
 [ "${available:-0}" -ge "$required" ] || { echo '可用内存不足以准备安全下载，备份文件已保留';exit 1; }
 sha=$(sha256sum "$file"|awk '{print $1}')
 { printf 'SCBACKUP1 %s %s\n' "$size" "$sha";base64 < "$file"; } > "$D/backup-download.txt.new"
 mv "$D/backup-download.txt.new" "$D/backup-download.txt"
fi
if [ "$mode" = remote ];then
 if ! remote_has core "$hash" tar.gz;then
  "$C/starts/download_core.sh"
  archive=/tmp/ShellCrash/CrashCore.tar.gz
  remote_put core "$archive" tar.gz >/dev/null
 fi
 remote_put info "$C/configs/core-installed.info" txt >/dev/null
 if [ "$(remote_transport)" = webdav ];then
  . "$C/starts/backup-set.sh"
  backup_set_publish "$file"
 else remote_put backup "$file" tar.gz > "$D/backup-sha";fi
 date +%s > "$C/configs/backup-time"
 rm -f "$C/configs/backup-pending" "$file"
fi
if [ "$mode" = remote ];then echo '完整备份已保存：应用、内核及已安装运行资源；当前设置保持不变'
else echo '应用与配置已导出；内核和临时运行资源需另行保存';fi
