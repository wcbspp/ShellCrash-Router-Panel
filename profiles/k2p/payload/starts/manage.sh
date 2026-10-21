#!/bin/sh
# The stock httpd command buffer requires small chunks. Keep their hot path
# independent of router configuration, logging and resource/status probes.
if [ "$1" = put ];then
 D=/tmp/sc-admin;umask 077;id=$2;chunk=$3
 [ "$#" = 3 ] && [ "${#id}" = 8 ] || exit 1
 case "$id" in *[!a-f0-9]*)exit 1;;esac
 IFS= read -r saved < "$D/id" || exit 1
 [ "$saved" = "$id" ] || exit 1
 IFS= read -r state < "$D/phase" || exit 1
 [ "$state" = uploading ] || exit 1
 [ "${#chunk}" -ge 5 ] && [ "${#chunk}" -le 20 ] || exit 1
 part=${chunk#????};seq=${chunk%"$part"}
 case "$seq" in *[!a-f0-9]*)exit 1;;esac
 case "$part" in *[!A-Za-z0-9+/=]*)exit 1;;esac
 [ -f "$D/upload.parts" ] && [ "$(wc -c < "$D/upload.parts")" -lt 400000 ] || exit 1
 printf '%s %s\n' "$seq" "$part" >> "$D/upload.parts"
 exit $?
fi
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
# Runs on demand through Padavan's authenticated administration interface.
C=/etc/storage/ShellCrash
export GOMEMLIMIT=12MiB
export GOGC=25
D=/tmp/sc-admin
umask 077
mkdir -p "$D"
act=$1
id=$2
phase(){ printf '%s\n' "$1" > "$D/phase"; [ -z "$2" ] || printf '%s\n' "$2" > "$D/message"; }
event(){ printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$1" >> "$D/events.log"; }
owner_live(){ p=$(cat "$D/operation.lock/owner" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
lock(){
 if ! mkdir "$D/operation.lock" 2>/dev/null; then
  owner_live && return 1
  if type native_clean_cache >/dev/null 2>&1;then native_clean_cache;fi;rm -rf "$D/native-previous";rm -f "$D/native-policy.input" "$D/native-resources.input";rm -f "$D/operation.lock/owner"; rmdir "$D/operation.lock" 2>/dev/null || return 1
  mkdir "$D/operation.lock" 2>/dev/null || return 1
 fi
 echo $$ > "$D/operation.lock/owner"
 if [ "$act" != restorego ];then revision=$(cat "$D/recovery-revision" 2>/dev/null);case "$revision" in ''|*[!0-9]*)revision=0;;esac;printf '%s\n' "$((revision+1))" > "$D/recovery-revision";fi
 trap 'if [ -n "$configuration_core_source" ];then configuration_core_release;fi;if [ "$act" = dns ]; then rm -rf "$D/dns"; fi; if [ "$act" = policy ] || [ "$act" = groupmode ]; then rm -rf "$D/policy"; fi; if [ "$act" = rules ]; then rm -rf "$D/rules"; fi; if [ "$act" = fetch ] || [ "$act" = fetchconvert ]; then rm -f "$D/ca.pem"; fi; if [ "$act" = apply ]; then rm -f "$D/previous.json" "$D/candidate.json" "$D/bounds.gz" "$D/bounds.json" "$D/check.json" "$D/upload.b64" "$D/upload.parts"; fi; if type native_clean_cache >/dev/null 2>&1;then native_clean_cache;fi;rm -rf "$D/native-previous";rm -f "$D/native-policy.input" "$D/native-resources.input";rm -f "$D/operation.lock/owner"; rmdir "$D/operation.lock" 2>/dev/null' EXIT
}
valid_id(){ printf '%s' "$1" | grep -Eq '^[a-f0-9]{8}$'; }
status(){
 . "$C/starts/cn_bypass.sh"
 if cb_enabled;then cb_refresh;fi
 cn_state=$(cat "$D/cn-state.json" 2>/dev/null)
 [ -n "$cn_state" ] || cn_state='{ "enabled":false,"active":false }'
 cn_safe=$(cb_safe);cn_warning=$(cb_warning)
 cn_state=$(printf '%s' "$cn_state"|sed 's/}$/,"eligible":"'"$cn_safe"'","warning":"'"$cn_warning"'"}/')
 . "$C/starts/resource_health.sh"
 resource_read
 pid=$(pidof CrashCore | awk '{print $1}'); running=false; [ -n "$pid" ] && running=true
 if [ "$running" = false ];then cn_state=$(printf '%s' "$cn_state"|sed 's/"active":true/"active":false/;s/"reason":"[A-Za-z]*"/"reason":"stopped"/');fi
 core_uptime=null
 if [ -n "$pid" ]; then
  core_uptime=$(awk 'NR==FNR {now=$1;next} {sub(/^[0-9]+ \(.*\) /, ""); if ($20 ~ /^[0-9]+$/ && $20/100<=now) {printf "%d", now-$20/100;ok=1}} END {if (!ok) printf "null"}' /proc/uptime "/proc/$pid/stat" 2>/dev/null)
  [ -n "$core_uptime" ] || core_uptime=null
 fi
 rss=0; [ -z "$pid" ] || rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status")
 mem=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
 mode=true; [ -f "$C/configs/panel-disabled" ] && mode=false
 ph=$(cat "$D/phase" 2>/dev/null); [ -n "$ph" ] || ph=idle
 msg=$(cat "$D/message" 2>/dev/null | base64 | tr -d '\n')
 url=$(cat "$C/configs/subscription.url.b64" 2>/dev/null | tr -d '\n')
 nonce=$(cat "$D/id" 2>/dev/null)
 active=false; owner_live && active=true
 recoveries=$(cat "$D/recoveries" 2>/dev/null); case "$recoveries" in ''|*[!0-9]*) recoveries=0;; esac
 autostart=true; [ ! -f "$C/.dis_startup" ] || autostart=false
 start_source=$(head -1 /tmp/ShellCrash/control-source 2>/dev/null); case "$start_source" in boot|tool|panel|watchdog|system) :;; *) start_source=unknown;; esac
 guard_mode=conservative; guard_active=false
 if [ "$running" = true ] && crontab -l 2>/dev/null | grep -q 'start_legacy_wd.sh shellcrash'; then guard_active=true; fi
 core_version=$(sed -n 's/^version=//p' "$C/configs/core-installed.info" 2>/dev/null)
 printf '%s' "$core_version" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}$' || core_version=unknown
 core_sha=$(sed -n 's/^sha256=//p' "$C/configs/core-installed.info" 2>/dev/null)
 printf '%s' "$core_sha" | grep -Eq '^[a-f0-9]{64}$' || core_sha=''
 core_blob=$(sed -n 's/^git_blob=//p' "$C/configs/core-installed.info" 2>/dev/null)
 printf '%s' "$core_blob" | grep -Eq '^[a-f0-9]{40}$' || core_blob=''
 . "$C/starts/mirror_lib.sh"
 mirror_base_b64=$(mirror_get base | base64 | tr -d '\n')
 mirror_target_b64=$(mirror_get target | base64 | tr -d '\n')
 mirror_last_b64=$(cat "$C/configs/mirror.last" 2>/dev/null | base64 | tr -d '\n')
 mirror_check='{}'; [ ! -s "$D/mirror-check.json" ] || mirror_check=$(cat "$D/mirror-check.json")
 mirror_ready=false; [ ! -s "$C/configs/mirror_key" ] || mirror_ready=true
 tool_version=$(tr -d '\r\n' < "$C/version");printf '%s' "$tool_version" | grep -Eq '^1\.[0-9]+\.[0-9]+(release|beta[0-9]+)$' || tool_version=unknown
 tool_check='{}';[ ! -s "$D/tool-check.json" ] || tool_check=$(cat "$D/tool-check.json")
 traffic_mode=$(cat /tmp/ShellCrash/traffic-mode 2>/dev/null);case "$traffic_mode" in rule|direct|global) :;; *) traffic_mode=rule;;esac
 . "$C/starts/transport_mode.sh"
 configured=$(transport_configured);mixed_available=false;transport_available && mixed_available=true
 transport_active=$(cat /tmp/ShellCrash/transport-runtime 2>/dev/null)
 [ "$running" = true ] || transport_active=''
 case "$transport_active" in redir|mixed|'') :;; *) transport_active=unknown;;esac
 printf '{"cn_bypass":%s,' "$cn_state"
 printf '"pid":%s,"transport":{"configured":"%s","active":"%s","mixed_available":%s},' "${pid:-0}" "$configured" "$transport_active" "$mixed_available"
 native_kind='';[ ! -f "$C/configs/native-profile" ] || native_kind=singbox
 printf '"template_kind":"%s","traffic_mode":"%s",' "$native_kind" "$traffic_mode"
 printf '"main_group":"%s","tool_version":"%s","tool_check":%s,"local_archive":false,"mirror_pending_b64":"%s",' "$PANEL_MAIN_GROUP" "$tool_version" "$tool_check" "$(cat "$C/configs/mirror.pending" 2>/dev/null | base64 | tr -d '\n')"
 printf '"quota_revision_b64":"%s",' "$(head -c 64 "$D/subscription-quota.revision" 2>/dev/null | base64 | tr -d '\n')"
 printf '"node_config_revision":"%s",' "$(md5sum "$C/jsons/config.json" | awk '{print $1}')"
 printf '"subscription_info_b64":"%s",' "$(head -c 8192 "$C/configs/subscription-state.json" 2>/dev/null | base64 | tr -d '\n')"
 remote_enabled=false;remote_enabled && remote_enabled=true
 remote_verified=false;remote_ready && remote_verified=true
 printf '"remote_enabled":%s,"remote_verified":%s,' "$remote_enabled" "$remote_verified"
 webdav_password_set=false;[ ! -s "$C/configs/webdav.auth" ] || webdav_password_set=true
 printf '"remote_transport":"%s","webdav_user_b64":"%s","webdav_password_set":%s,' "$(remote_transport)" "$(cat "$C/configs/webdav.user" 2>/dev/null | base64 | tr -d '\n')" "$webdav_password_set"
 remote_checked=$(cat "$C/configs/remote.checked" 2>/dev/null);case "$remote_checked" in ''|*[!0-9]*)remote_checked=0;;esac
 printf '"remote_checked":%s,"remote_application_b64":"%s","remote_config_b64":"%s","remote_baseline_b64":"%s",' "$remote_checked" "$(head -c 2048 "$D/remote-application.json" 2>/dev/null | base64 | tr -d '\n')" "$(head -c 2048 "$D/remote-config.json" 2>/dev/null | base64 | tr -d '\n')" "$(head -c 2048 "$D/remote-baseline.json" 2>/dev/null | base64 | tr -d '\n')"
 printf '"core_uptime_seconds":%s,' "$core_uptime"
 core_check='{}'; [ ! -s "$D/core-check.json" ] || core_check=$(cat "$D/core-check.json")
 rules_count=$(head -1 "$C/configs/rules.meta" 2>/dev/null); case "$rules_count" in ''|*[!0-9]*) rules_count=4305;; esac
 dns_mode=$(sed -n 's/^dns_mod=//p' "$C/configs/ShellCrash.cfg" | head -1); case "$dns_mode" in mix|fake-ip|redir_host) :;; *) dns_mode=unknown;; esac
 rules_date=$(sed -n '2p' "$C/configs/rules.meta" 2>/dev/null | base64 | tr -d '\n')
 cleanup='{}'; [ ! -s "$D/cleanup.json" ] || cleanup=$(cat "$D/cleanup.json")
 printf '"autostart":%s,"guard_mode":"%s","guard_runtime":"%s","guard_active":%s,"start_source":"%s","guard_owner":"shellcrash","memory_limits":{"warning_mb":%s,"protect_mb":%s,"cleanup_mb":%s},"cleanup":%s,"mirror_base_b64":"%s","mirror_target_b64":"%s","mirror_last_b64":"%s","mirror_ready":%s,"mirror_check":%s,"dns_mode":"%s","rules_count":%s,"rules_date_b64":"%s","running":%s,"enabled":%s,"rss_kb":%s,"free_kb":%s,"recoveries":%s,"active":%s,"phase":"%s","message_b64":"%s","url_b64":"%s","id":"%s","core_version":"%s","core_sha":"%s","core_blob":"%s","core_check":%s,"available_kb":%s,"pressure":"%s","shmem_kb":%s,"slab_kb":%s,"tcp_kb":%s,"conntrack":%s}\n' "$autostart" "$guard_mode" "$guard_mode" "$guard_active" "$start_source" "$rh_warning_mb" "$rh_protect_mb" "$rh_cleanup_mb" "$cleanup" "$mirror_base_b64" "$mirror_target_b64" "$mirror_last_b64" "$mirror_ready" "$mirror_check" "$dns_mode" "$rules_count" "$rules_date" "$running" "$mode" "${rss:-0}" "${mem:-0}" "$recoveries" "$active" "$ph" "$msg" "$url" "$nonce" "$core_version" "$core_sha" "$core_blob" "$core_check" "$rh_available" "$rh_pressure" "$rh_shmem" "$rh_slab" "$rh_tcp" "$rh_conn"
}
trim_logs(){
 . "$C/starts/resource_health.sh"
 resource_cleanup
}
stop_core(){
 old=$(pidof CrashCore)
 "$C/start.sh" stop >> "$D/worker.log" 2>&1
 tries=0
 while [ "$tries" -lt 20 ]; do
  live=false
  for p in $old; do kill -0 "$p" 2>/dev/null && live=true; done
  [ "$live" = true ] || return 0
  sleep 1; tries=$((tries+1))
 done
 return 1
}
start_core(){
 [ -z "$configuration_core_source" ] || configuration_core_materialize || return 1
 # Keep FD3 through the boot handoff: native ash children cannot resolve the
 # verified /proc FD link after explicitly closing it. The owning transaction
 # releases its handle on commit/rollback; boot children are bounded.
 SC_REUSE_RUNNING_CORE=${configuration_core_source:+1} SC_CORE_UPDATE_TMPFS=${core_update_tmpfs:-0} SC_CONTROL_SOURCE=panel "$C/starts/panel_boot.sh" >> "$D/worker.log" 2>&1
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 tries=0
 while [ "$tries" -lt 30 ]; do
  if [ -n "$(pidof CrashCore)" ] && curl -fsS --connect-timeout 1 --max-time 2 -H "Authorization: Bearer $secret" http://${PANEL_LAN_IP}:9999/version >/dev/null 2>&1; then return 0; fi
  sleep 1; tries=$((tries+1))
 done
 return 1
}
save_safe(){
 waited=0
 while [ -d /tmp/shellcrash-storage-save.lock ] && [ "$waited" -lt 75 ]; do sleep 1; waited=$((waited+1)); done
 "$C/starts/save_storage.sh" >> "$D/worker.log" 2>&1
}
fail(){ phase error "$1"; event "$1"; }
case "$act" in
 nodeping) exec sh "$C/starts/node-ping.sh" k2p "$id" "$3";;
 nodepingresult) if [ -f "$D/nodepingresult.json" ];then head -c 512 "$D/nodepingresult.json";else printf '{"state":"idle"}\n';fi;;
 quota|quotacheck) mode=read;[ "$act" != quotacheck ] || mode=check;exec sh "$C/starts/subscription-quota.sh" k2p "$mode";;
 fetchconvert)
  owner_live && exit 1
  valid_id "$id" || exit 1;echo "$id" > "$D/id"
  fail 'K2P 仅支持服务商直取订阅，未发送给转换服务';exit 1;;
 uploadreceipt)
  IFS= read -r nonce < "$D/id" || exit 1
  valid_id "$nonce" || exit 1
  IFS= read -r ph < "$D/phase" || exit 1
  [ "$ph" = uploading ] || exit 1
  receipt=$(sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' | sha256sum | awk '{print $1}')
  printf '{"id":"%s","phase":"uploading","sha256":"%s"}\n' "$nonce" "$receipt";exit 0;;
 fetch|fetchconvert|fetchpanel|apply|rules|dns|policy|groupmode|grouplayout|coreupdate|mirrorsync)
  . "$C/starts/resource_health.sh"; resource_read
  if [ "$rh_pressure" = protect ]; then
   owner_live && exit 1
   valid_id "$id" && echo "$id" > "$D/id"
   fail memory_protected; exit 1
  fi;;
esac
case "$act" in apply|dns|rules|policy|groupmode|grouplayout|transport|coreupdate) . "$C/starts/config_core.sh" || exit 1;;esac
case "$act" in
 restorego)
  valid_id "$id" || exit 1
  ticket=$3;case "$ticket" in *[!a-f0-9]*)exit 1;;esac
  [ "${#ticket}" = 16 ] || exit 1
  lock || exit 1;echo "$id" > "$D/id"
  phase working '正在复核确认凭据'
  trap - EXIT
  exec sh "$C/starts/recovery-dispatch.sh" k2p "$id" "$ticket";;
 cnbypass)
  valid_id "$id" || exit 1;case "$3" in 0|1) :;;*)exit 1;;esac
  lock || exit 1;echo "$id" > "$D/id";phase working '正在应用国内 IP 绕过'
  . "$C/starts/cn_bypass.sh";cb_save "$3" || exit 1;;
 traffic)
  . "$C/starts/traffic_sample.sh";traffic_sample;exit 0;;
 transport)
  valid_id "$id" || exit 1
  lock || exit 1;echo "$id" > "$D/id";phase working '正在切换接管方式'
  . "$C/starts/transport_mode.sh";transport_apply "$3" || exit 1;;
 proxymode)
  valid_id "$id" || exit 1;case "$3" in rule|direct|global) :;; *) exit 1;;esac
  lock || exit 1;echo "$id" > "$D/id";phase working '正在切换流量接管'
  . "$C/starts/traffic_mode.sh"
  if traffic_mode_apply "$3";then phase done '流量模式已生效';else fail '流量模式切换失败，已尝试恢复原设置';exit 1;fi;;
 advanced)
  valid_id "$id" || exit 1
  lock || exit 1;echo "$id" > "$D/id";phase working '正在准备高级面板'
  if sh "$C/starts/dashboard-install.sh" "$C" > "$D/worker.log" 2>&1;then
   ln -sfn /tmp/ShellCrash-dashboard /opt/share/www/custom/sc-dashboard
   phase done '高级面板已准备'
  else fail '高级面板下载或校验失败，请查看运行日志';fi;;
 grouplayout)
  valid_id "$id" || exit 1;lock || exit 1;echo "$id" > "$D/id"
  GROUP_JOB=2;. "$C/starts/policy_update.sh";;
 trim) trim_logs;;
 configprofile) head -c 262145 "$C/jsons/config.json";;
 nodeprofile) awk '/^"outbounds":/{sub(/^"outbounds":/,"");sub(/,$/,"");print;exit}' "$C/jsons/config.json";;
 converters)
  f="$C/configs/servers.list"; [ -s "$f" ] || f="$C/servers.list"
  awk -v cfgfile="$C/configs/ShellCrash.cfg" -f "$C/padavan/subscription_defaults.awk" "$f";;
 remoteconnection) . "$C/starts/remote.sh";dav_status;;
 remotecatalog) . "$C/starts/remote.sh";dav_catalog;;
 recoveryplan) if [ -s "$D/recovery-plan.json" ];then head -c 8192 "$D/recovery-plan.json";else printf '{"verified":false}\n';fi;;
 status) status;;
 incidents) [ ! -f "$D/incidents.log" ] || tail -100 "$D/incidents.log";;
 memory) [ ! -f "$D/resources.csv" ] || awk -F, 'NF==15{print $1 "," $2 "," $3 "," $4 "," $5 ",0"}' "$D/resources.csv";;
 cleanup)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  phase cleaning cleaning_memory
  . "$C/starts/resource_health.sh"
  rh_manual=1
  if resource_cleanup; then phase done memory_cleaned; else fail cleanup_busy; fi;;
 memcfg)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  . "$C/starts/memory_settings.sh";;
 mirrorsave|mirrorsync|mirrorverify|mirrortest)
  valid_id "$id" || exit 1
  if [ "$act" = mirrorsave ] || [ "$act" = mirrortest ]; then [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] || exit 1; fi
  lock || exit 1
  echo "$id" > "$D/id"
  . "$C/starts/mirror_update.sh";;
 restorecheck)
  valid_id "$id" || exit 1
  [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] || exit 1
  [ "$(cat "$D/kind" 2>/dev/null)" = restore ] || exit 1
  [ "$(wc -c < "$D/upload.parts")" -le 1024 ] || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  sort "$D/upload.parts" | awk '!seen[$1]++ {printf "%s", $2}' > "$D/restore-request.b64"
  if ! base64 -d "$D/restore-request.b64" > "$D/upload-restore";then rm -f "$D/restore-request.b64" "$D/upload-restore";fail '恢复检查请求传输不完整';exit 1;fi
  rm -f "$D/restore-request.b64"
  printf '%s' "$id" > "$D/upload-id-restore"
  phase working '正在核对备份组件，当前代理保持运行'
  if "$C/starts/recovery-check.sh" k2p "$id" > "$D/recovery-result.log" 2>&1;then phase done '组件大小与 SHA256 校验通过；当前设备未改动'
  else fail "$(head -c 512 "$D/recovery-result.log")";fi
  rm -f "$D/upload.parts";;
 baselinecreate)
  valid_id "$id" || exit 1
  case "$3" in create|replace) :;;*)exit 1;;esac
  lock || exit 1
  echo "$id" > "$D/id"
  phase working '正在生成并校验独立基础版本，当前代理保持运行'
  if "$C/starts/backup-baseline-run.sh" k2p "$3" > "$D/baseline-result.log" 2>&1;then
   # The baseline lives on DAV; local time bookkeeping is not its authority.
   # A Storage failure must not falsely report that remote publication failed.
   if save_safe;then phase done '基础版本已独立保存并校验'
   else phase done '基础版本已保存；本机备份时间记录未持久化，请稍后重试保存';fi
  else fail '基础版本未更新，请查看日志；原基础版本保留';fi;;
 backuplocal|backupremote)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  phase working '正在备份应用'
  backupmode=local;[ "$act" != backupremote ] || backupmode=remote
  if "$C/starts/backup-app.sh" "$backupmode" >> "$D/worker.log" 2>&1;then
   [ "$backupmode" != remote ] || save_safe || { fail persistent_save_failed;exit 1; }
   # Padavan's authenticated HTTP server only serves known suffixes.
   # Binary .js responses are parsed by Padavan EJ and lose NUL bytes.
   # Authenticated ASCII transport is decoded and SHA256-checked by the client.
   rm -f /opt/share/www/custom/sc-backup.js
   ln -sf "$D/backup-download.txt" /opt/share/www/custom/sc-backup.asp
   phase done '应用备份完成'
  else fail '应用备份失败，请查看日志';fi;;
 toolcheck|toolupdate)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  phase working updating_tool_release
  if SC_TOOL_JOB=1 "$C/starts/tool_update.sh" k2p "$( [ "$act" = toolcheck ] && echo check || echo update )" >> "$D/worker.log" 2>&1;then phase done tool_updated;else fail tool_update_rejected_previous_kept;fi;;
 corecheck|coreupdate)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  : > "$D/worker.log"
  . "$C/starts/core_update.sh";;
 dns)
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ "$(cat "$D/kind")" = filter ] || exit 1
  lock || exit 1
  . "$C/starts/dns_update.sh";;
 groupmode)
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ "$(cat "$D/kind")" = group ] || exit 1
  lock || exit 1
  . "$C/starts/group_update.sh";;
 policy)
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ "$(cat "$D/kind")" = policy ] || exit 1
  lock || exit 1
  . "$C/starts/policy_update.sh";;
 rules)
  valid_id "$id" || exit 1
  lock || exit 1
  echo "$id" > "$D/id"
  . "$C/starts/rules_update.sh";;
 clear)
  lock || exit 1
  phase clearing clearing_logs
  # Keep system OOM evidence and the separate recovery counter.
  for f in "$D/events.log" "$D/subscription-tool.log" /tmp/ShellCrash/core.log /tmp/ShellCrash/ShellCrash.log "$D/fetch-error" "$D/worker.log" "$D/logs.out"; do
   [ ! -f "$f" ] || : > "$f"
  done
  event 'Logs cleared'; phase done logs_cleared;;
 logs)
  printf '=== Management ===\n'; tail -40 "$D/events.log" 2>/dev/null
  printf '\n=== Resource pressure ===\n'; tail -20 "$D/pressure.log" 2>/dev/null
  printf '\n=== Proxy ===\n'; tail -65 /tmp/ShellCrash/core.log 2>/dev/null
  printf '\n=== ShellCrash ===\n'; tail -20 /tmp/ShellCrash/ShellCrash.log 2>/dev/null
  printf '\n=== Subscription download ===\n'; tail -5 "$D/fetch-error" 2>/dev/null
  printf '\n=== ShellCrash subscription ===\n'; tail -30 "$D/subscription-tool.log" 2>/dev/null
  printf '\n=== Last operation ===\n'; tail -20 "$D/worker.log" 2>/dev/null;;
 new)
  valid_id "$id" || exit 1
  owner_live && exit 1
  kind=$3; case "$kind" in source|bounds|profile|filter|mirror|policy|group|restore) :;; *) exit 1;; esac
  [ "$(cat "$D/phase" 2>/dev/null)" = uploading ] && [ -f "$D/upload.parts" ] && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ "$kind" = "$(cat "$D/kind" 2>/dev/null)" ] && exit 0
  if [ "$kind" = bounds ] || [ "$kind" = profile ]; then [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ -s "$D/candidate.url.b64" ] || exit 1; else
   rm -f "$D/sub.raw" "$D/candidate.url.b64" "$D/previous.json" "$D/candidate.json" "$D/bounds.gz" "$D/bounds.json" "$D/check.json"
   echo "$id" > "$D/id"
  fi
  : > "$D/upload.parts"; echo "$kind" > "$D/kind"; phase uploading upload_ready;;
 put)
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] || exit 1
  chunk=$3; printf '%s' "$chunk" | grep -Eq '^[a-f0-9]{4}[A-Za-z0-9+/=]{1,16}$' || exit 1
  [ "$(stat -c %s "$D/upload.parts")" -lt 400000 ] || exit 1
  seq=$(printf '%s' "$chunk" | cut -c 1-4); part=$(printf '%s' "$chunk" | cut -c 5-)
  # Short indexed records can be replayed safely; assembly discards duplicates.
  printf '%s %s\n' "$seq" "$part" >> "$D/upload.parts";;
 fetch|fetchconvert|fetchpanel)
  [ "$(cat "$D/phase" 2>/dev/null)" = downloaded ] && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && exit 0
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && [ "$(cat "$D/kind")" = source ] || exit 1
  lock || exit 1
  phase fetching downloading_subscription; : > "$D/subscription-tool.log"; rm -f "$D/subscription.error" "$D/subscription.endpoint" "$D/subscription.progress"; : > "$D/worker.log"
  sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' > "$D/upload.b64"
  base64 -d "$D/upload.b64" > "$D/native-source" 2>/dev/null || { fail invalid_upload; exit 1; }
  url=$(head -1 "$D/native-source")
  [ "${#url}" -le 2048 ] || { fail invalid_subscription_url; exit 1; }
  case "$url" in https://*|http://*) :;; *) fail invalid_subscription_url; exit 1;; esac
  printf '%s' "$url" | grep -q '[[:space:]]' && { fail invalid_subscription_url; exit 1; }
  printf '%s' "$url" | base64 | tr -d '\n' > "$D/candidate.url.b64"
  method=direct;[ "$act" != fetchconvert ] || method=convert;fetcher=panel;rm -f "$D/subscription-fetch.info"
  policy=${3:-s0a1};case "$policy" in s[0-8]a[01]) :;; *) fail invalid_arguments;exit 1;; esac
  if [ "$act" != fetchpanel ] && "$C/starts/subscription_tool.sh" k2p "$method" "$policy";then
   fetcher=shellcrash;event 'Subscription retrieved through ShellCrash'
  elif [ "$method" = direct ];then
   event 'ShellCrash direct retrieval failed; trying previous direct reader'
   # TLS verification remains enabled; neither the URL nor credentials enter logs.
   cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$D/ca.pem"
   if ! curl -4 --cacert "$D/ca.pem" --noproxy '*' -fsS --connect-timeout 10 --max-time 25 --max-filesize 524288 "$url" -o "$D/sub.raw" 2> "$D/fetch-error"; then
    if [ -n "$(pidof CrashCore)" ]; then
      event 'Direct subscription download failed; retrying through active proxy'
      if ! curl -4 --cacert "$D/ca.pem" --noproxy '' --proxy http://${PANEL_LAN_IP}:7890 -fsS --connect-timeout 10 --max-time 20 --max-filesize 524288 "$url" -o "$D/sub.raw" 2>> "$D/fetch-error"; then
       fail subscription_download_failed; rm -f "$D/sub.raw"; exit 1
      fi
    else
      fail subscription_download_failed; rm -f "$D/sub.raw"; exit 1
    fi
   fi
  else
   reason=$(head -1 "$D/subscription.error" 2>/dev/null); case "$reason" in subscription_http_*|subscription_dns_failed|subscription_connect_failed|subscription_timeout|subscription_tls_failed) :;; *) reason=subscription_download_failed;; esac
   fail "$reason";rm -f "$D/sub.raw";exit 1
  fi
  [ -s "$D/sub.raw" ] || { fail empty_subscription; exit 1; }
  [ "$act" != fetchpanel ] || method=panel
  printf 'id=%s\nmethod=%s\nfetcher=%s\nconverter_policy=%s\n' "$id" "$method" "$fetcher" "$policy" > "$D/subscription-attempt.info"
  phase downloaded subscription_downloaded; event 'Subscription downloaded; active configuration unchanged';;
 start|stop|restart)
  lock || exit 1
  : > "$D/worker.log"; phase "$act" service_operation; event "Service $act requested"
  if [ "$act" = stop ]; then
   echo 1 > "$C/configs/panel-disabled"
   stop_core || { fail service_stop_failed; exit 1; }
   if ! save_safe; then fail persistent_save_failed; exit 1; fi
  else
   if [ "$act" = restart ] && [ -n "$(pidof CrashCore)" ];then
    . "$C/starts/resource_health.sh"
    . "$C/starts/config_core.sh"
    configuration_core_prepare || exit 1
   fi
   rm -f "$C/configs/panel-disabled"
   if [ "$act" = restart ]; then stop_core || { fail service_stop_failed; exit 1; }; fi
   [ -n "$(pidof CrashCore)" ] || start_core || { fail service_start_failed; exit 1; }
   save_safe || { fail persistent_save_failed; exit 1; }
  fi
  phase done service_operation_complete; event "Service $act completed";;
 apply)
  [ "$(cat "$D/phase" 2>/dev/null)" = done ] && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] && exit 0
  valid_id "$id" && [ "$id" = "$(cat "$D/id" 2>/dev/null)" ] || exit 1
  upload_kind=$(cat "$D/kind");case "$upload_kind" in bounds|profile) :;;*)exit 1;;esac
  reset_count=0
  rm -f "$D/native-policy.tsv" "$D/native-policy.rules" "$D/native-resources.tsv"
  lock || exit 1
  : > "$D/worker.log"; phase applying validating_configuration
  sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' > "$D/upload.b64"
  if ! base64 -d "$D/upload.b64" > "$D/bounds.gz" 2>/dev/null; then fail invalid_upload; exit 1; fi
  magic=$(head -c 2 "$D/bounds.gz" | base64 | tr -d '\n')
  if [ "$magic" = H4s= ]; then gzip -dc "$D/bounds.gz" 2>/dev/null | head -c 262145 > "$D/bounds.json"; else head -c 262145 "$D/bounds.gz" > "$D/bounds.json"; fi
  [ "$(stat -c %s "$D/bounds.json")" -le 262144 ] || { fail invalid_upload; exit 1; }
  parser=panel
  if [ "$upload_kind" = profile ];then
   . "$C/starts/native_profile.sh"
   native_profile_candidate "$D/bounds.json" >> "$D/worker.log" 2>&1 || {
    reason='完整订阅合并或规则资源验证失败，当前配置保留'
    case "$(tail -1 "$D/worker.log")" in
     *'规则资源暂存内存不足'*)reason='规则资源暂存内存不足，未停止内核，当前配置保留';;
     *'2 MB 上限'*)reason='订阅规则资源超出 K2P 的 2 MB 限制，当前配置保留';;
    esac
    fail "$reason";exit 1;
   }
   parser=native
  else
   grep -q '^\[' "$D/bounds.json" || { fail invalid_upload;exit 1; }
  reset_count=$(grep -o '"_subscription_reset":true' "$D/bounds.json" | wc -l)
  sed 's/,"_subscription_reset":true//g' "$D/bounds.json" > "$D/bounds-clean.json";mv "$D/bounds-clean.json" "$D/bounds.json"
  awk 'FNR==NR{b=$0;next} /^"outbounds":/{print "\"outbounds\":" b ",";next}{print}' "$D/bounds.json" "$C/jsons/config.json" > "$D/candidate.json"
  grep -q '^"outbounds":' "$C/jsons/config.json" || { fail configuration_template_missing; exit 1; }
  if [ -s "$C/configs/group_modes.tsv" ];then
   awk -v modes="$C/configs/group_modes.tsv" -f "$C/starts/group_mode.awk" "$D/candidate.json" > "$D/modes-candidate.json" || { fail invalid_upload;exit 1; }
   mv "$D/modes-candidate.json" "$D/candidate.json"
  fi
  awk -v main="$PANEL_MAIN_GROUP" -f "$C/starts/group_layout.awk" "$D/candidate.json" > "$D/layout-candidate.json" || { fail configuration_check_failed_previous_kept;exit 1; }
  mv "$D/layout-candidate.json" "$D/candidate.json"
  if [ -f "$C/configs/native-profile" ];then
   fallback='{"rule_set":[{"type":"local","tag":"cn","format":"binary","path":"/tmp/ShellCrash/ruleset/cn.srs"}],"rules":[{"inbound":"dns-in","action":"hijack-dns"},{"ip_is_private":true,"outbound":"direct"},{"clash_mode":"Direct","outbound":"direct"},{"clash_mode":"Global","outbound":"GLOBAL"},{"network":"udp","outbound":"direct"},{"rule_set":["cn"],"outbound":"direct"}],"final":"'"$PANEL_MAIN_GROUP"'","default_domain_resolver":"dns-direct"}'
   awk -v route="$fallback" '/^"route":/{print "\"route\":" route ",";next}{print}' "$D/candidate.json" > "$D/fallback.json";mv "$D/fallback.json" "$D/candidate.json"
   . "$C/starts/native_profile.sh"
   cp "$C/configs/policy.tsv" "$D/native-policy.input"
   : > "$D/native-policy.rules"
   awk -v input="$D/native-policy.input" -v oldfile="$C/configs/policy.rules" -v metadata="$D/native-policy.tsv" -v compiled="$D/native-policy.rules" -f "$C/starts/policy_merge.awk" "$D/candidate.json" > "$D/fallback.json" || { fail configuration_check_failed_previous_kept;exit 1; }
   mv "$D/fallback.json" "$D/candidate.json"
  fi
  fi
  mkdir -p "$D/native-previous"
  for name in native-profile native-resources.tsv policy.tsv policy.rules;do
   rm -f "$D/native-previous/$name";[ ! -f "$C/configs/$name" ] || cp "$C/configs/$name" "$D/native-previous/$name"
  done
  restore_native_metadata(){ for name in native-profile native-resources.tsv policy.tsv policy.rules;do if [ -f "$D/native-previous/$name" ];then cp "$D/native-previous/$name" "$C/configs/$name";else rm -f "$C/configs/$name";fi;done; }

  was_running=0; [ -z "$(pidof CrashCore)" ] || was_running=1
  cp "$C/jsons/config.json" "$D/previous.json"
  cp "$C/configs/subscription.url.b64" "$D/previous.url.b64" 2>/dev/null || : > "$D/previous.url.b64"
  cp "$C/configs/subscription-state.json" "$D/previous.subscription-state" 2>/dev/null || : > "$D/previous.subscription-state"
  configuration_core_prepare || exit 1
  if [ "$was_running" = 1 ]; then
   CRASHDIR="$C" sh -c ' . "$CRASHDIR/libs/get_config.sh"; . "$CRASHDIR/libs/check_cmd.sh"; . "$CRASHDIR/libs/web_save.sh"; web_save' >> "$D/worker.log" 2>&1 || { fail selection_save_failed; exit 1; }
   stop_core || { fail service_stop_failed; exit 1; }
  fi
  # Only outbounds change; avoid parsing the unchanged large DNS/CN tables twice.
  { printf '{"outbounds":'; cat "$D/bounds.json"; printf ',"route":{"final":"%s"}}\n' "$PANEL_MAIN_GROUP"; } > "$D/check.json"
  if ! configuration_core_materialize || ! GOMEMLIMIT=12MiB GOGC=25 /tmp/ShellCrash/CrashCore check -D /tmp/ShellCrash -c "$D/candidate.json" >> "$D/worker.log" 2>&1; then
   rm -f /tmp/ShellCrash/CrashCore; [ "$was_running" = 0 ] || start_core
   fail configuration_check_failed_previous_kept; exit 1
  fi
  cp "$D/candidate.json" "$C/jsons/config.json"; cp "$D/candidate.url.b64" "$C/configs/subscription.url.b64"
  if [ "$parser" = native ];then
   echo singbox > "$C/configs/native-profile";cp "$D/native-resources.tsv" "$C/configs/native-resources.tsv"
  else rm -f "$C/configs/native-profile" "$C/configs/native-resources.tsv";fi
  if [ -f "$D/native-policy.tsv" ];then cp "$D/native-policy.tsv" "$C/configs/policy.tsv";cp "$D/native-policy.rules" "$C/configs/policy.rules";fi
  if [ "$id" = "$(sed -n 's/^id=//p' "$D/subscription-attempt.info")" ];then
   method=$(sed -n 's/^method=//p' "$D/subscription-attempt.info");fetcher=$(sed -n 's/^fetcher=//p' "$D/subscription-attempt.info");policy=$(sed -n 's/^converter_policy=//p' "$D/subscription-attempt.info")
   case "$method:$fetcher:$policy" in direct:shellcrash:s[0-8]a[01]|convert:shellcrash:s[0-8]a[01]|direct:panel:s[0-8]a[01]|panel:panel:s[0-8]a[01])
    converter='';template='';tool='';if [ "$fetcher" = shellcrash ];then converter=$(sed -n 's/^converter_b64=//p' "$D/subscription-fetch.info");template=$(sed -n 's/^template_b64=//p' "$D/subscription-fetch.info");tool=$(sed -n 's/^tool_version_b64=//p' "$D/subscription-fetch.info");fi
    custom=$(sed -n 's/^custom_b64=//p' "$D/subscription-fetch.info");template_url=$(sed -n 's/^template_url_b64=//p' "$D/subscription-fetch.info");ua=$(sed -n 's/^ua_b64=//p' "$D/subscription-fetch.info")
    ua_override=$(sed -n 's/^ua=//p' "$D/native-source" | head -1);case "$ua_override" in *[!A-Za-z0-9+/=]*) ua_override='';;esac;[ "${#ua_override}" -le 256 ] || ua_override=''
    exclude=$(sed -n 's/^exclude=//p' "$D/native-source");case "$exclude" in *[!A-Za-z0-9+/=]*) exclude='';;esac;[ "${#exclude}" -le 1368 ] || exclude='';exclude_mode=keyword;case "$(sed -n 's/^exclude_mode=//p' "$D/native-source")" in cmVnZXg=) exclude_mode=regex;;YXV0bw==) exclude_mode=auto;;esac
    hash=$(sha256sum "$D/bounds.json" | awk '{print $1}');retained=false;[ "$parser" != native ] || [ ! -s "$D/native-resource-retained" ] || retained=true
    printf '{"method":"%s","fetcher":"%s","parser":"%s","core_kind":"singbox","converter_policy":"%s","converter_b64":"%s","template_b64":"%s","tool_version_b64":"%s","custom_b64":"%s","template_url_b64":"%s","ua_b64":"%s","ua_override_b64":"%s","exclude_b64":"%s","exclude_mode":"%s","reset_count":%s,"rule_resources_retained":%s,"config_id":"%s","applied_at":%s}\n' "$method" "$fetcher" "$parser" "$policy" "$converter" "$template" "$tool" "$custom" "$template_url" "$ua" "$ua_override" "$exclude" "$exclude_mode" "$reset_count" "$retained" "$hash" "$(date +%s)" > "$C/configs/subscription-state.json.new"
    mv "$C/configs/subscription-state.json.new" "$C/configs/subscription-state.json";;
   esac
  fi

  if ! save_safe; then
   restore_native_metadata
   cp "$D/previous.json" "$C/jsons/config.json"; cp "$D/previous.url.b64" "$C/configs/subscription.url.b64"
   if [ -s "$D/previous.subscription-state" ];then cp "$D/previous.subscription-state" "$C/configs/subscription-state.json";else rm -f "$C/configs/subscription-state.json";fi
   rm -f /tmp/ShellCrash/CrashCore; [ "$was_running" = 0 ] || start_core
   fail persistent_save_failed_previous_kept; exit 1
  fi
  if [ "$was_running" = 1 ] && ! start_core; then
   restore_native_metadata
   cp "$D/previous.json" "$C/jsons/config.json"; cp "$D/previous.url.b64" "$C/configs/subscription.url.b64"
   if [ -s "$D/previous.subscription-state" ];then cp "$D/previous.subscription-state" "$C/configs/subscription-state.json";else rm -f "$C/configs/subscription-state.json";fi
   save_safe; start_core
   fail start_failed_previous_restored; exit 1
  fi
  [ "$was_running" = 1 ] || rm -f /tmp/ShellCrash/CrashCore
  [ "$parser" != native ] || native_resources_backup >> "$D/worker.log" 2>&1
  phase done subscription_updated; event 'Subscription validated, saved and applied'
  sh "$C/starts/subscription-quota.sh" k2p auto || :
  rm -f "$D/previous.json" "$D/candidate.json" "$D/bounds.gz" "$D/bounds.json" "$D/upload.b64" "$D/upload.parts" "$D/check.json";;
 *) exit 1;;
esac
