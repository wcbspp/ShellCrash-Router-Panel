#!/bin/sh
# AX5 transaction, armed by a validated native or computer plan. Always run the
# copied worker outside the application being restored.
set -eu
umask 077
C=/data/ShellCrash
R=/tmp/ShellCrash
T=/data/ShellCrash-tool
X=${1:-}
case "$X" in /tmp/sc-restore-[a-f0-9][a-f0-9]*) :;;*)exit 2;;esac
[ "${X%/*}" = /tmp ] && [ -f "$X/plan" ] || exit 2
field(){ sed -n "s/^$1=//p" "$X/plan" | head -1; }
ID=$(field id);case "$ID" in ''|*[!a-f0-9]*)exit 2;;esac
[ "${#ID}" = 8 ] && [ "$X" = "/tmp/sc-restore-$ID" ] || exit 2
STATE=preparing;STOPPED=0;MUTATED=0;FINISHED=0
phase(){
 STATE=$1;msg=$2
 printf '{"id":"%s","phase":"%s","active":true,"message_b64":"%s"}\n' "$ID" "$STATE" "$(printf '%s' "$msg" | base64 | tr -d '\n')" > "$R/job.json.new"
 mv "$R/job.json.new" "$R/job.json"
 printf '%s %s\n' "$(date +%s)" "$STATE" >> "$X/events"
 date +%s > "$R/operation.lock.time"
}
hash(){ openssl dgst -sha256 "$1" | awk '{print $NF}'; }
checked(){ [ -f "$1" ] && [ "$(wc -c < "$1" | tr -d ' ')" = "$2" ] && [ "$(hash "$1")" = "$3" ]; }
available(){ awk '/MemAvailable:/{print $2;exit}' /proc/meminfo; }
wait_stopped(){ for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15;do [ -z "$(pidof CrashCore)" ] && return 0;sleep 1;done;return 1; }
stop(){ printf '0\n' > "$C/configs/enabled";/etc/init.d/shellcrash stop;wait_stopped; }
clear_runtime(){ rm -f "$R/CrashCore" "$R/config.yaml" "$R/fakeip.db" "$R/cache.db" "$R/core.pid" "$R/service-ready"; }
clear_app(){
 # Only the application's documented roots. Firmware/network/plugins untouched.
 rm -rf "$C/ui" "$C/ax5" "$C/ruleset" "$C/cache/targets" "$T" || return 1
 # Leave recovery credentials on flash throughout replacement, even if power
 # fails. Other configuration is replaced, never merged with stale files.
 for entry in "$C/configs"/* "$C/configs"/.[!.]*;do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  case "${entry##*/}" in recovery-enabled|mirror.conf|webdav.auth|webdav.user|mirror-id|mirror_key|mirror_known_hosts|remote.verified|remote.checked)continue;;esac
  rm -rf "$entry" || return 1
 done
 rm -f "$C/cache/core.env" "$C/cache/core.sha256" || return 1
 mkdir -p "$C/configs" "$C/cache"
}
credentials(){
 for name in recovery-enabled mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do
  if [ -f "$X/credentials/$name" ];then cp "$X/credentials/$name" "$C/configs/$name" || return 1
  else rm -f "$C/configs/$name" || return 1;fi
 done
}
boot_integration(){
 cp "$C/ax5/shellcrash.init" /etc/init.d/shellcrash
 chmod 755 /etc/init.d/shellcrash
 if [ -f "$T/.dis_startup" ];then /etc/init.d/shellcrash disable;else /etc/init.d/shellcrash enable;fi
}
start_and_check(){
 enabled=$1
 printf '%s\n' "$enabled" > "$C/configs/enabled"
 [ "$enabled" = 1 ] || return 0
 printf 'restore\n' > "$R/control-source.pending"
 /etc/init.d/shellcrash start || return 1
 for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20;do
  if [ -s "$R/service-ready" ] && [ -n "$(pidof CrashCore)" ] && curl --noproxy '*' -fsS --max-time 2 -H "$(cat "$C/configs/api-header")" http://127.0.0.1:9999/version -o "$X/version.json";then
   if SC_RESTORE_HEALTH_FILE="$X/version.json" SC_RESTORE_HEALTH_VERSION="$2" lua -e 'local f=assert(io.open(os.getenv("SC_RESTORE_HEALTH_FILE")));local v=require("cjson").decode(f:read("*a"));f:close();assert(type(v.version)=="string" and v.version:gsub("^v","")==os.getenv("SC_RESTORE_HEALTH_VERSION"):gsub("^v",""))';then return 0;fi
  fi
  sleep 1
 done
 return 1
}
rollback(){
 phase rollingback '恢复未完成，正在还原操作前状态' || return 1
 stop || return 1
 clear_runtime || return 1
 rm -rf "$X/target" || return 1
 rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz" "$X/core.tar.gz" || return 1
 if [ "$MUTATED" = 1 ];then
  clear_app || return 1
  tar -xzf "$X/rollback-application.tar.gz" -C "$C" || return 1
  [ ! -d "$C/ShellCrash-tool" ] || mv "$C/ShellCrash-tool" "$T" || return 1
  if [ -f "$X/rollback-core.tar.gz" ];then
   rm -f "$C/cache/core-armv7.tar.gz" || return 1
   cp "$X/rollback-core.tar.gz" "$C/cache/core-armv7.tar.gz" || return 1
   rm -f "$X/rollback-core.tar.gz" || return 1
  fi
  credentials || return 1
  rm -rf /tmp/ShellCrash-dashboard || return 1
  tar -xzf "$X/rollback-runtime.tar.gz" -C /tmp || return 1
  cp "$X/init.previous" /etc/init.d/shellcrash || return 1
  chmod 755 /etc/init.d/shellcrash || return 1
  if [ -f "$T/.dis_startup" ];then /etc/init.d/shellcrash disable || return 1;else /etc/init.d/shellcrash enable || return 1;fi
 fi
 [ "$(hash "$C/cache/core-armv7.tar.gz")" = "$OLD_CORE" ] || return 1
 start_and_check "$ORIGINAL_ENABLED" "$(field previous_core_version)"
}
finish(){
 code=$?
 trap - EXIT INT TERM
 if [ "$FINISHED" != 1 ];then
  if [ "$STOPPED" = 1 ];then
   if rollback;then STATE=rolledback;else STATE=rollback_failed;fi
  else STATE=rejected;fi
 fi
 # Rollback evidence is deliberately kept. Never delete this transaction on error.
 printf '{"id":"%s","state":"%s","manifest_sha256":"%s","core_sha256":"%s","time":%s}\n' "$ID" "$STATE" "$(field manifest_sha256)" "${NEW_CORE:-unknown}" "$(date +%s)" > "$X/result.json"
 if [ -f "$X/recovery-session.lua" ];then
  lua "$X/recovery-session.lua" result "/tmp/sc-preflight-$ID" && cp "/tmp/sc-preflight-$ID/public.json" "$R/recovery-plan.json.new" && mv "$R/recovery-plan.json.new" "$R/recovery-plan.json" || :
 fi
 case "$STATE" in done)message='备份恢复完成';;rolledback)message='恢复未完成，已还原操作前状态';;rollback_failed)message='自动回退失败，请保留恢复目录并通过 SSH 检查';;*)message='恢复检查未通过，未覆盖应用';;esac
 printf '{"id":"%s","phase":"%s","active":false,"message_b64":"%s"}\n' "$ID" "$([ "$STATE" = done ] && echo done || echo error)" "$(printf '%s' "$message" | base64 | tr -d '\n')" > "$R/job.json.new"
 mv "$R/job.json.new" "$R/job.json"
 rm -f "$R/operation.lock/owner"
 rmdir "$R/operation.lock" 2>/dev/null || :
 rm -f "$R/operation.lock.time"
 exit "$code"
}
if [ "${SC_RESTORE_HANDOFF:-}" = "$ID" ] && [ "$(cat "$R/operation.lock/owner" 2>/dev/null)" = "$$" ];then :
elif ! mkdir "$R/operation.lock";then printf '{"id":"%s","state":"busy"}\n' "$ID" > "$X/result.json";exit 3;fi
echo $$ > "$R/operation.lock/owner"
trap finish EXIT
trap 'exit 1' INT TERM
phase preparing '正在保存操作前恢复点'
. "$C/ax5/remote.sh"
remote_transfer_ready && [ "$(remote_transport)" = webdav ] || exit 1
[ "$(remote_fingerprint)" = "$(field remote_fingerprint)" ] || exit 1
NEW_CORE=$(field core_sha256);OLD_CORE=$(hash "$C/cache/core-armv7.tar.gz")
[ "$OLD_CORE" = "$(field previous_core_sha256)" ] || exit 1
sh "$C/ax5/verify-core.sh" && gzip -t "$C/cache/core-armv7.tar.gz"
ORIGINAL_ENABLED=$(cat "$C/configs/enabled");case "$ORIGINAL_ENABLED" in 0|1) :;;*)exit 1;;esac
protect=$(field protect_kb);case "$protect" in ''|*[!0-9]*)exit 1;;esac
[ "$protect" -ge 12288 ] && [ "$(available)" -ge "$((protect+2048))" ] || exit 1
mkdir "$X/credentials"
for name in recovery-enabled mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do
 [ ! -f "$C/configs/$name" ] || cp "$C/configs/$name" "$X/credentials/$name"
done
cp /etc/init.d/shellcrash "$X/init.previous"
lua "$C/ax5/state.lua" save-selection
sh "$C/ax5/backup-app.sh" local > "$X/rollback-backup.log" 2>&1
mv "$R/application-backup.tar.gz" "$X/rollback-application.tar.gz"
D=$R;protect_kb=$protect
. "$C/ax5/backup-set.sh"
backup_resources_pack >> "$X/rollback-backup.log" 2>&1
mv "$R/runtime-assets-backup.tar.gz" "$X/rollback-runtime.tar.gz"
# remote.sh and backup helpers use short global names; restore private paths now.
C=/data/ShellCrash;R=/tmp/ShellCrash;T=/data/ShellCrash-tool
phase checkpointing '正在校验 WebDAV 操作前回退点'
CHECKPOINT="$(dav_base)/recoveries/$ID"
dav_mkdir "$(dav_base)/recoveries" && dav_mkdir "$CHECKPOINT"
dav_store_file "$X/rollback-application.tar.gz" "$CHECKPOINT/application.tar.gz"
dav_store_file "$X/rollback-runtime.tar.gz" "$CHECKPOINT/runtime-assets.tar.gz"
core_url=$(dav_object core "$OLD_CORE" tar.gz)
copy_code=$(dav_curl -X COPY -H "Destination: $CHECKPOINT/core.tar.gz" -H 'Overwrite: F' -o /dev/null -w '%{http_code}' "$core_url") || copy_code=000
case "$copy_code" in 201|204)[ "$(dav_read_hash "$CHECKPOINT/core.tar.gz")" = "$OLD_CORE" ];;*)dav_store_file "$C/cache/core-armv7.tar.gz" "$CHECKPOINT/core.tar.gz";;esac
app_hash=$(hash "$X/rollback-application.tar.gz");runtime_hash=$(hash "$X/rollback-runtime.tar.gz")
app_size=$(wc -c < "$X/rollback-application.tar.gz" | tr -d ' ');runtime_size=$(wc -c < "$X/rollback-runtime.tar.gz" | tr -d ' ');core_size=$(wc -c < "$C/cache/core-armv7.tar.gz" | tr -d ' ')
set_hash=$(printf '%s\n%s\n%s\n' "$app_hash" "$OLD_CORE" "$runtime_hash" | remote_hash)
printf '{"format":2,"scope":"full-application-baseline","model":"AX5","created":%s,"core_kind":"%s","core_version":"%s","core_sha256":"%s","sha256":"%s","files":[{"name":"application.tar.gz","size":%s,"sha256":"%s"},{"name":"core.tar.gz","size":%s,"sha256":"%s"},{"name":"runtime-assets.tar.gz","size":%s,"sha256":"%s"}]}\n' "$(date +%s)" "$(field previous_core_kind)" "$(field previous_core_version)" "$OLD_CORE" "$set_hash" "$app_size" "$app_hash" "$core_size" "$OLD_CORE" "$runtime_size" "$runtime_hash" > "$X/rollback-manifest.json"
dav_store_file "$X/rollback-manifest.json" "$CHECKPOINT/manifest.json"
dav_store_file "$X/init.previous" "$CHECKPOINT/init.previous"
phase stopping '操作前备份已保存，正在暂停代理'
STOPPED=1
stop
clear_runtime
phase downloading '正在获取并校验目标组件'
# Guard actual memory after stop, before allocating any archives or extraction.
need=$(field peak_bytes);case "$need" in ''|*[!0-9]*)exit 1;;esac
[ "$(available)" -ge "$((protect+(need+1023)/1024))" ] || exit 1
if [ "$NEW_CORE" != "$OLD_CORE" ];then cp "$C/cache/core-armv7.tar.gz" "$X/rollback-core.tar.gz";fi
for name in application runtime-assets core;do
 if [ "$name" = core ] && [ "$NEW_CORE" = "$OLD_CORE" ];then continue;fi
 key=$name;[ "$name" != runtime-assets ] || key=runtime
 path=$(field "${key}_path");size=$(field "${key}_size");expected=$(field "${key}_sha256")
 remote_transfer_ready || exit 1
 dav_curl --fail --max-time 90 --max-filesize "$size" "$(dav_base)/$path" -o "$X/$name.tar.gz"
 checked "$X/$name.tar.gz" "$size" "$expected"
 gzip -t "$X/$name.tar.gz"
done
lua "$X/archive-validator.lua" application "$X/application.tar.gz" "$NEW_CORE"
lua "$X/archive-validator.lua" runtime-assets "$X/runtime-assets.tar.gz" "$NEW_CORE"
core_archive="$C/cache/core-armv7.tar.gz";[ "$NEW_CORE" = "$OLD_CORE" ] || core_archive="$X/core.tar.gz"
lua "$X/archive-validator.lua" core "$core_archive" "$NEW_CORE"
mkdir "$X/target"
tar -xzf "$X/application.tar.gz" -C "$X/target"
[ -f "$X/target/cache/core.sha256" ] || printf '%s\n' "$NEW_CORE" > "$X/target/cache/core.sha256"
[ "$(cat "$X/target/cache/core.sha256" | tr -d ' \n')" = "$NEW_CORE" ]
TARGET_ENABLED=$(cat "$X/target/configs/enabled");case "$TARGET_ENABLED" in 0|1) :;;*)exit 1;;esac
# Credentials always belong to the current server. Extracted backups cannot change them.
for name in recovery-enabled mirror.conf webdav.auth webdav.user mirror-id mirror_key mirror_known_hosts remote.verified remote.checked;do rm -f "$X/target/configs/$name";done
[ -f "$X/target/backup.info" ] && [ -x "$X/target/ax5/prepare.sh" ]
# Page-origin transactions check the candidate with the actual trusted core
# before the first application write, after freeing the running core's memory.
if [ -f "$X/restore-config.lua" ];then
 phase validating '正在隔离校验候选配置，尚未覆盖应用'
 cp "$X/target/configs/config.json" "$X/config.original.json"
 ln -s "$X/target" "$X/app";mkdir "$X/runtime"
 tar -xzf "$X/runtime-assets.tar.gz" -C "$X/runtime"
 lua "$X/restore-config.lua" "$X"
 tar -xzf "$C/cache/core-armv7.tar.gz" -C "$R" CrashCore
 chmod 700 "$R/CrashCore"
 [ "$(hash "$R/CrashCore")" = "$(field binary_sha256)" ]
 if [ "$(field previous_core_kind)" = meta ];then
  sed "s|SAFE_PATHS=/data/ShellCrash|SAFE_PATHS=$X|" "$C/ax5/check-binary.sh" > "$X/check-binary.sh"
  sh "$X/check-binary.sh" meta "$R/CrashCore" -t -d "$X/runtime" -f "$X/config.check.json" >> "$X/check.log" 2>&1
 else GOMEMLIMIT=12MiB GOGC=25 "$R/CrashCore" check -D "$X/runtime" -c "$X/config.check.json" >> "$X/check.log" 2>&1;fi
 # Startup owns materializing its executable. Release this check-only copy so
 # the existing boot budget does not count the same 32 MB file twice.
 rm -f "$R/CrashCore"
 rm -rf "$X/runtime";rm -f "$X/app" "$X/config.original.json" "$X/config.check.json"
fi
phase applying '目标文件已校验，正在恢复应用和配置'
MUTATED=1
clear_app
# Move verified staged roots onto flash; app is small, core archive handled separately.
for name in configs ui ax5 ruleset cache;do
 if [ -d "$X/target/$name" ];then mkdir -p "$C/$name";cp -a "$X/target/$name/." "$C/$name/";fi
done
if [ -d "$X/target/ShellCrash-tool" ];then cp -a "$X/target/ShellCrash-tool" "$T";fi
credentials
printf '0\n' > "$C/configs/enabled"
if [ "$NEW_CORE" != "$OLD_CORE" ];then
 rm -f "$C/cache/core-armv7.tar.gz"
 cp "$X/core.tar.gz" "$C/cache/core-armv7.tar.gz"
fi
[ "$(hash "$C/cache/core-armv7.tar.gz")" = "$NEW_CORE" ]
rm -rf /tmp/ShellCrash-dashboard
tar -xzf "$X/runtime-assets.tar.gz" -C /tmp
boot_integration
sync
if [ "$(field rehearsal_failure)" = after-write ];then echo 'Controlled rehearsal failure after write' >&2;exit 1;fi
rm -rf "$X/target";rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz" "$X/core.tar.gz"
boot_core=$(field boot_core_bytes);boot_private=$(field boot_private_kb)
required=$((protect+boot_private+(boot_core+1023)/1024));actual=$(available)
[ "$actual" -ge "$required" ] || { echo "启动预算拒绝：可用 ${actual} KB，需要 ${required} KB" >&2;exit 1; }
phase starting '正在校验配置并启动恢复后的内核'
start_and_check "$TARGET_ENABLED" "$(field target_core_version)"
phase checking '正在核对恢复状态'
[ "$(hash "$C/cache/core-armv7.tar.gz")" = "$NEW_CORE" ]
STATE=done;FINISHED=1
