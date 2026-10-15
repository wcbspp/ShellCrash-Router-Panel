#!/bin/sh
# Replaces the authenticated job process, retaining the operation lock and PID.
set -eu
umask 077
profile=$1;id=$2;token=$3
case "$profile" in ax5)C=/data/ShellCrash;D=/tmp/ShellCrash;;k2p)C=/etc/storage/ShellCrash;D=/tmp/sc-admin;;*)exit 2;;esac
case "$id:$token" in *[!a-f0-9:]*)exit 2;;esac
[ "${#id}" = 8 ] && [ "${#token}" = 16 ] || exit 2
P=/tmp/sc-preflight-$id;X=/tmp/sc-restore-$id
# The existing authenticated API/job acquired the lock. Claim it before any
# blocking validation so another operation cannot steal a long transaction.
[ -d "$D/operation.lock" ] || exit 3
printf '%s\n' $$ > "$D/operation.lock/owner"
finish(){
 status=$?;trap - EXIT
 if [ -f "$P/recovery-session.lua" ];then lua "$P/recovery-session.lua" invalidate "$P" "$token" || :;fi
 message=$(printf '%s' '恢复未启动；确认凭据过期或设备状态已变化，请重新检查' | base64 | tr -d '\n')
 if [ "$profile" = ax5 ];then
  printf '{"id":"%s","phase":"error","active":false,"message_b64":"%s"}\n' "$id" "$message" > "$D/job.json.new";mv "$D/job.json.new" "$D/job.json"
 else printf 'error\n' > "$D/phase";printf '%s\n' '恢复未启动，请重新检查备份和确认凭据' > "$D/message";fi
 rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || :
 if [ -f "$P/public.json" ] && [ ! -f "$X/result.json" ];then
  mkdir -p "$X"
  printf '{"id":"%s","state":"rejected"}\n' "$id" > "$X/result.json"
  lua "$P/recovery-session.lua" result "$P" && cp "$P/public.json" "$D/recovery-plan.json.new" && mv "$D/recovery-plan.json.new" "$D/recovery-plan.json" || :
 fi
 exit "$status"
}
trap finish EXIT
[ -f "$C/configs/recovery-enabled" ] || exit 1
export C D
helper=$C/ax5;[ "$profile" != k2p ] || helper=$C/starts
. "$helper/remote.sh"
remote_ready && [ "$(remote_transport)" = webdav ] || exit 1
lua "$P/recovery-live.lua" "$profile" "$(remote_fingerprint)" > "$P/current.json"
# Validate the local binding before any authenticated request to a changed peer.
SC_RECOVERY_P=$P lua -e 'local j=require("cjson");local p=os.getenv("SC_RECOVERY_P");local function r(n)local f=assert(io.open(p.."/"..n));local v=j.decode(f:read("*a"));f:close();return v end;assert(r("current.json").remote_fingerprint==r("live.json").remote_fingerprint,"remote identity changed")'
lua "$P/recovery-session.lua" check "$P" "$token"
remote_transfer_ready
manifest_path=$(SC_RECOVERY_P=$P lua -e 'local f=assert(io.open(os.getenv("SC_RECOVERY_P").."/selection.json"));local s=require("cjson").decode(f:read("*a"));f:close();assert(s.manifest_path:match("^[%w_./%-]+$")and not s.manifest_path:find("..",1,true));print(s.manifest_path)')
(status=0;dav_curl --fail --max-time 10 --max-filesize 16384 "$(dav_base)/$manifest_path" || status=$?;printf '%s\n' "$status" > "$P/recheck.status") | head -c 16385 > "$P/recheck-manifest.json"
[ "$(cat "$P/recheck.status")" = 0 ] && [ "$(wc -c < "$P/recheck-manifest.json")" -le 16384 ]
current_hash=$(remote_hash < "$P/recheck-manifest.json")
SC_RECOVERY_P=$P SC_RECOVERY_SHA=$current_hash lua -e 'local f=assert(io.open(os.getenv("SC_RECOVERY_P").."/selection.json"));local s=require("cjson").decode(f:read("*a"));f:close();assert(s.manifest_sha256==os.getenv("SC_RECOVERY_SHA"),"manifest changed")'
[ ! -e "$X" ] || { echo 'transaction already exists; do not resubmit' >&2;exit 1; }
lua "$P/recovery-live.lua" "$profile" "$(remote_fingerprint)" > "$P/current.json"
lua "$P/recovery-session.lua" take "$P" "$token"
mkdir "$X"
cp "$P/live.json" "$X/live.json";cp "$P/restore-config.lua" "$X/restore-config.lua";cp "$P/plan" "$X/plan";cp "$P/restore-worker.sh" "$X/worker.sh";cp "$P/archive-validator.lua" "$X/archive-validator.lua";cp "$P/recovery-session.lua" "$X/recovery-session.lua"
lua "$P/recovery-session.lua" running "$P"
cp "$P/public.json" "$D/recovery-plan.json.new";mv "$D/recovery-plan.json.new" "$D/recovery-plan.json"
SC_RESTORE_HANDOFF=$id;export SC_RESTORE_HANDOFF
trap - EXIT
# All descriptors were detached by the existing authenticated job launcher.
# exec retains PID/lock ownership and frees this shell before restoring files.
exec sh "$X/worker.sh" "$X" > "$X/worker.log" 2>&1
