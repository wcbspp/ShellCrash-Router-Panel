#!/bin/sh
# Computer-validated K2P same-core recovery prototype. No browser dispatch.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH GOMEMLIMIT=12MiB GOGC=25
set -eu
umask 077
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
R=/tmp/ShellCrash
X=${1:-}
case "$X" in /tmp/sc-restore-[a-f0-9][a-f0-9]*) :;;*)exit 2;;esac
field(){ sed -n "s/^$1=//p" "$X/plan" | head -1; }
ID=$(field id)
case "$ID" in ''|*[!a-f0-9]*)exit 2;;esac
[ "${#ID}" = 8 ] && [ "$X" = "/tmp/sc-restore-$ID" ] || exit 2
STATE=preparing;STOPPED=0;MUTATED=0;FINISHED=0
phase(){ STATE=$1;printf '%s\n' "$1" > "$D/phase";printf '%s\n' "$2" > "$D/message";printf '%s %s\n' "$(date +%s)" "$1" >> "$X/events"; }
hash(){ sha256sum "$1" | awk '{print $1}'; }
available(){ awk '/MemAvailable:/{print $2;exit}' /proc/meminfo; }
checked(){ [ "$(wc -c < "$1" | tr -d ' ')" = "$2" ] && [ "$(hash "$1")" = "$3" ]; }
stop(){
 # Native stop removes watchdog cron entries before it terminates the core.
 # Keep those entries and the original enable flag if termination fails.
 crontab -l > "$X/stop-cron.previous" || return 1
 had_disabled=0;[ ! -f "$C/configs/panel-disabled" ] || had_disabled=1
 : > "$C/configs/panel-disabled"
 "$C/start.sh" stop >> "$X/service.log" 2>&1 || :
 for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20;do [ -z "$(pidof CrashCore)" ] && return 0;sleep 1;done
 crontab "$X/stop-cron.previous" || return 1
 [ "$had_disabled" = 1 ] || rm -f "$C/configs/panel-disabled"
 return 1
}
clear_runtime(){
 rm -f "$R/CrashCore" "$R/CrashCore.tar.gz" "$R/jsons/config.json" || return 1
 rm -rf "$R/ruleset" /tmp/ShellCrash-dashboard || return 1
}
# Only a single named member goes to stdout, then to a bounded isolated file.
# Never extract network tar entries by path. The verified binary SHA comes
# from the fully inspected local bundle, so a changed stream cannot be applied.
stream_core(){
 url=$1;destination=$2
 rm -f "$X/curl.code" "$X/core-tar.error" "$destination"
 ( code=0;dav_curl --fail --max-time 120 --max-filesize "$(field core_size)" "$url" || code=$?;printf '%s\n' "$code" > "$X/curl.code" ) |
  head -c "$(( $(field core_size)+1 ))" |
  tar -zxOf - "$(field core_member)" 2> "$X/core-tar.error" |
  head -c "$(( $(field binary_size)+1 ))" > "$destination"
 [ "$(cat "$X/curl.code")" = 0 ] && [ ! -s "$X/core-tar.error" ] || return 1
 checked "$destination" "$(field binary_size)" "$(field binary_sha256)" || return 1
 chmod 755 "$destination"
}
clear_app(){
 for folder in ui padavan starts libs tools menus task jsons yamls ruleset;do rm -rf "$C/$folder" || return 1;done
 for entry in "$C/configs"/* "$C/configs"/.[!.]*;do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  case "${entry##*/}" in mirror.conf|webdav.auth|webdav.user|mirror-id|mirror_key|mirror_known_hosts|remote.verified|remote.checked)continue;;esac
  rm -rf "$entry" || return 1
 done
 for name in start.sh menu.sh init.sh version task_en.list task.list singbox_providers.list servers.list clash_providers.list fallback_filter.list fake_ip_filter.list cn_ipv6.txt .dis_startup;do rm -f "$C/$name" || return 1;done
 mkdir -p "$C/configs"
}
credentials(){
 for name in mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do
  if [ -f "$X/credentials/$name" ];then cp "$X/credentials/$name" "$C/configs/$name" || return 1
  else rm -f "$C/configs/$name" || return 1;fi
 done
}
startup(){ if [ "$1" = 0 ];then : > "$C/.dis_startup";else rm -f "$C/.dis_startup";fi; }
start_check(){
 enabled=$1;mode=$2
 if [ "$enabled" = 0 ];then : > "$C/configs/panel-disabled";return 0;fi
 rm -f "$C/configs/panel-disabled"
 SC_REUSE_RUNNING_CORE=1 SC_CONTROL_SOURCE=panel "$C/starts/panel_boot.sh" >> "$X/service.log" 2>&1 || return 1
 . "$C/starts/panel_env.sh" || return 1
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 curl --noproxy '*' -fsS --max-time 4 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/version" > "$X/version.json" || return 1
 [ "$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$X/version.json" | sed 's/^sing-box //')" = "$(field core_version)" ] || return 1
 if [ "$mode" != rule ];then . "$C/starts/traffic_mode.sh";traffic_mode_apply "$mode" || return 1;fi
}
restore_runtime(){
 rm -rf /tmp/ShellCrash-dashboard "$R/ruleset" || return 1
 tar -xzf "$1" -C /tmp || return 1
}
rollback(){
 phase rollingback '恢复未完成，正在还原操作前状态' || return 1
 stop || return 1
 clear_runtime || return 1
 rm -rf "$X/target";rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz"
 if [ "$MUTATED" = 1 ];then
  clear_app || return 1
  tar -xzf "$X/rollback-application.tar.gz" -C "$C" || return 1
  credentials || return 1
  startup "$(field previous_autostart)" || return 1
 fi
 restore_runtime "$X/rollback-runtime.tar.gz" || return 1
 stream_core "$CHECKPOINT/core.tar.gz" "$R/CrashCore" || return 1
 if [ "$(field previous_enabled)" = 1 ];then rm -f "$C/configs/panel-disabled";fi
 sh "$X/save_storage.sh" >> "$X/storage.log" 2>&1 || return 1
 start_check "$(field previous_enabled)" "$(field previous_mode)"
}
finish(){
 code=$?;trap - EXIT INT TERM
 if [ "$FINISHED" != 1 ];then
  if [ "$STOPPED" = 1 ];then if rollback;then STATE=rolledback;else STATE=rollback_failed;fi
  else STATE=rejected;fi
 fi
 printf '{"id":"%s","state":"%s","manifest_sha256":"%s","time":%s}\n' "$ID" "$STATE" "$(field manifest_sha256)" "$(date +%s)" > "$X/result.json"
 case "$STATE" in done)msg='备份恢复完成';;rolledback)msg='恢复未完成，已还原操作前状态';;rollback_failed)msg='回退失败，请保留事务目录并通过 SSH 检查';;*)msg='恢复预检未通过，未覆盖应用';;esac
 phase "$([ "$STATE" = done ] && echo done || echo error)" "$msg"
 rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || :
 exit "$code"
}
mkdir "$D/operation.lock" || exit 3
echo $$ > "$D/operation.lock/owner"
trap finish EXIT
trap 'exit 1' INT TERM
phase preparing '正在保存操作前恢复点'
for name in start.sh menu.sh menus/bot_tg_service.sh;do [ -s "$C/$name" ] || { echo "当前程序缺少 $name，未暂停服务";exit 1; };done
. "$C/starts/remote.sh"
remote_transfer_ready && [ "$(remote_transport)" = webdav ] || exit 1
[ "$(remote_fingerprint)" = "$(field remote_fingerprint)" ] || exit 1
[ "$(sed -n 's/^sha256=//p' "$C/configs/core-installed.info")" = "$(field core_sha256)" ] || exit 1
protect=$(field protect_kb)
[ "$(available)" -ge "$((protect+3072))" ] || exit 1
mkdir "$X/credentials"
for name in mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do [ ! -f "$C/configs/$name" ] || cp "$C/configs/$name" "$X/credentials/$name";done
cp "$C/starts/save_storage.sh" "$X/save_storage.sh"
CRASHDIR=$C;export CRASHDIR
. "$C/starts/panel_env.sh"
secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
curl --noproxy '*' -fsS --max-time 5 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/proxies" -o "$X/proxies.json"
[ -s "$X/proxies.json" ]
rm -f "$R/web_save"
(set +eu;. "$C/libs/check_cmd.sh";. "$C/libs/get_config.sh";. "$C/libs/web_save.sh";get_save(){ cat "$X/proxies.json"; };web_save)
sh "$C/starts/backup-app.sh" local > "$X/backup.log" 2>&1
mv "$D/application-backup.tar.gz" "$X/rollback-application.tar.gz"
rm -f "$D/backup-download.txt"
protect_kb=$protect
. "$C/starts/backup-set.sh"
backup_resources_pack >> "$X/backup.log" 2>&1
mv "$D/runtime-assets-backup.tar.gz" "$X/rollback-runtime.tar.gz"
C=/etc/storage/ShellCrash;D=/tmp/sc-admin;R=/tmp/ShellCrash
phase checkpointing '正在校验 WebDAV 操作前恢复点'
CHECKPOINT="$(dav_base)/recoveries/$ID"
dav_mkdir "$(dav_base)/recoveries" && dav_mkdir "$CHECKPOINT"
dav_store_file "$X/rollback-application.tar.gz" "$CHECKPOINT/application.tar.gz"
dav_store_file "$X/rollback-runtime.tar.gz" "$CHECKPOINT/runtime-assets.tar.gz"
code=$(dav_curl -X COPY -H "Destination: $CHECKPOINT/core.tar.gz" -H 'Overwrite: F' -o /dev/null -w '%{http_code}' "$(dav_object core "$(field core_sha256)" tar.gz)") || code=000
case "$code" in 201|204) :;;*)echo '服务器不支持独立内核 COPY，未暂停服务';exit 1;;esac
[ "$(dav_read_hash "$CHECKPOINT/core.tar.gz")" = "$(field core_sha256)" ]
app_hash=$(hash "$X/rollback-application.tar.gz");runtime_hash=$(hash "$X/rollback-runtime.tar.gz")
app_size=$(wc -c < "$X/rollback-application.tar.gz" | tr -d ' ');runtime_size=$(wc -c < "$X/rollback-runtime.tar.gz" | tr -d ' ')
set_hash=$(printf '%s\n%s\n%s\n' "$app_hash" "$(field core_sha256)" "$runtime_hash" | remote_hash)
printf '{"format":2,"scope":"full-application-baseline","model":"K2P","created":%s,"sha256":"%s","core_kind":"singbox","core_version":"%s","core_sha256":"%s","files":[{"name":"application.tar.gz","size":%s,"sha256":"%s"},{"name":"core.tar.gz","size":%s,"sha256":"%s"},{"name":"runtime-assets.tar.gz","size":%s,"sha256":"%s"}]}\n' "$(date +%s)" "$set_hash" "$(field core_version)" "$(field core_sha256)" "$app_size" "$app_hash" "$(field core_size)" "$(field core_sha256)" "$runtime_size" "$runtime_hash" > "$X/rollback-manifest.json"
dav_store_file "$X/rollback-manifest.json" "$CHECKPOINT/manifest.json"
# The host-inspected same-core binary is also the exact previous core.
phase stopping '回退点已校验，正在暂停代理'
STOPPED=1;stop
clear_runtime
[ "$(available)" -ge "$((protect+($(field peak_bytes)+1023)/1024))" ]
[ "$(df -Pk /tmp | awk 'END{print $4}')" -ge "$((($(field tmp_bytes)+1023)/1024))" ]
phase downloading '正在分组件获取并校验目标文件'
for key in application runtime;do
 name=application;[ "$key" != runtime ] || name=runtime-assets
 remote_transfer_ready
 dav_curl --fail --max-time 90 --max-filesize "$(field ${key}_size)" "$(dav_base)/$(field ${key}_path)" -o "$X/$name.tar.gz"
 checked "$X/$name.tar.gz" "$(field ${key}_size)" "$(field ${key}_sha256)"
 gzip -t "$X/$name.tar.gz"
done
stream_core "$(dav_base)/$(field core_path)" "$R/CrashCore"
mkdir "$X/target"
tar -xzf "$X/application.tar.gz" -C "$X/target"
for name in mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do rm -f "$X/target/configs/$name";done
phase applying '目标文件已校验，正在恢复应用和配置'
MUTATED=1;clear_app
for name in configs ui padavan starts libs tools menus task jsons yamls ruleset;do
 [ ! -d "$X/target/$name" ] || { mkdir -p "$C/$name";cp -a "$X/target/$name/." "$C/$name/"; }
done
for name in start.sh menu.sh init.sh version task_en.list task.list singbox_providers.list servers.list clash_providers.list fallback_filter.list fake_ip_filter.list cn_ipv6.txt;do [ ! -f "$X/target/$name" ] || cp -a "$X/target/$name" "$C/$name";done
credentials
startup "$(field target_autostart)"
: > "$C/configs/panel-disabled"
restore_runtime "$X/runtime-assets.tar.gz"
rm -rf "$X/target";rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz"
[ "$(available)" -ge "$((protect+6144))" ]
phase validating '正在检查目标内核与配置'
"$R/CrashCore" check -D "$R" -c "$C/jsons/config.json" >> "$X/check.log" 2>&1
if [ "$(field rehearsal_failure)" = after-write ];then echo 'Controlled rehearsal failure after write' >&2;exit 1;fi
[ "$(field target_enabled)" != 1 ] || rm -f "$C/configs/panel-disabled"
phase persisting '正在保存已恢复的持久配置'
sh "$X/save_storage.sh" >> "$X/storage.log" 2>&1
phase starting '正在启动并核对恢复后的内核'
start_check "$(field target_enabled)" "$(field target_mode)"
STATE=done;FINISHED=1
