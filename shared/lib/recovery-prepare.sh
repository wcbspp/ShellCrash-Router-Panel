#!/bin/sh
# Called under the authenticated operation lock, after strict manifest/SHA check.
set -eu
umask 077
profile=$1;id=$2;metadata=$3
case "$profile" in ax5)C=/data/ShellCrash;D=/tmp/ShellCrash;helper=$C/ax5;;k2p)C=/etc/storage/ShellCrash;D=/tmp/sc-admin;helper=$C/starts;;*)exit 2;;esac
case "$id" in ''|*[!a-f0-9]*)exit 2;;esac
[ "${#id}" = 8 ] || exit 2
X=/tmp/sc-preflight-$id
mkdir "$X"
step=setup
cleanup(){ code=$?;if [ "$code" != 0 ];then echo "原生预检未通过：$step（退出码 $code）" >&2;fi;rm -rf "$X/app" "$X/runtime";rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz" "$X/config.original.json" "$X/config.check.json"; }
trap cleanup EXIT
# These copies are outside the application that will later be replaced.
for name in restore-archive.lua restore-config.lua recovery-live.lua recovery-session.lua restore-worker.sh;do cp "$helper/$name" "$X/$name";done
cp "$X/restore-archive.lua" "$X/archive-validator.lua"
cp "$helper/recovery-status.html" /tmp/sc-recovery-status.html
if [ "$profile" = ax5 ];then ln -sf /tmp/sc-recovery-status.html /www/sc-recovery-status.html;else cp /tmp/sc-recovery-status.html /opt/share/www/custom/sc-recovery-status.asp;fi
cp "$metadata/plan.json" "$X/backup.json";cp "$metadata/manifest.json" "$X/manifest.json";cp "$metadata/selection.json" "$X/selection.json"
export C D
. "$helper/remote.sh"
remote_transfer_ready
lua "$X/recovery-live.lua" "$profile" "$(remote_fingerprint)" > "$X/live.json"
lua "$X/recovery-session.lua" plan "$X"
# Write the preliminary, server-only plan needed by the K native preflight.
SC_RECOVERY_X=$X lua -e 'local x=os.getenv("SC_RECOVERY_X");local j=require("cjson");local f=assert(io.open(x.."/server-plan.json"));local p=j.decode(f:read("*a"));f:close();f=assert(io.open(x.."/plan","wb"));for k,v in pairs(p)do f:write(k,"=",tostring(v),"\n")end;f:close()'
field(){ sed -n "s/^$1=//p" "$X/plan" | head -1; }
step=core-binary
# Core archive SHA was verified by recovery-check. Stream the named binary only;
# bound output and require it to equal the current executable, with no core copy.
core_url="$(dav_base)/$(field core_path)";core_size=$(field core_size)
(status=0;dav_curl --fail --max-time 90 --max-filesize "$core_size" "$core_url" || status=$?;printf '%s\n' "$status" > "$X/core-list.status") |
 head -c "$((core_size+1))" | tar -tzf - 2> "$X/core-list.error" | head -c 128 > "$X/core-members"
[ "$(cat "$X/core-list.status")" = 0 ] && [ ! -s "$X/core-list.error" ]
member=$(cat "$X/core-members");case "$member" in CrashCore|./CrashCore) :;;*)echo 'unsupported core archive members' >&2;exit 1;;esac
binary_size=$(field binary_size)
(status=0;dav_curl --fail --max-time 90 --max-filesize "$core_size" "$core_url" || status=$?;printf '%s\n' "$status" > "$X/core-binary.status") |
 head -c "$((core_size+1))" | tar -xzOf - "$member" 2> "$X/core-binary.error" | head -c "$((binary_size+1))" | remote_hash > "$X/core-binary.sha256"
[ "$(cat "$X/core-binary.status")" = 0 ] && [ ! -s "$X/core-binary.error" ] && [ "$(cat "$X/core-binary.sha256")" = "$(field binary_sha256)" ]
printf 'core_member=%s\n' "$member" >> "$X/plan"
SC_RECOVERY_X=$X SC_RECOVERY_MEMBER=$member lua -e 'local x=os.getenv("SC_RECOVERY_X");local j=require("cjson");local f=assert(io.open(x.."/server-plan.json"));local p=j.decode(f:read("*a"));f:close();p.core_member=os.getenv("SC_RECOVERY_MEMBER");f=assert(io.open(x.."/server-plan.json","wb"));f:write(j.encode(p));f:close()'
step=archive-and-config
if [ "$profile" = k2p ];then
 sh "$helper/restore-preflight.sh" "$X"
else
 compressed_kb=$((($(field application_size)+$(field runtime_size)+1023)/1024))
 [ "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)" -ge "$(( $(field protect_kb)+compressed_kb+3072 ))" ]
 [ "$(df -Pk /tmp | awk 'END{print $4}')" -ge "$((compressed_kb+3072))" ]
 download(){
  (code=0;dav_curl --fail --max-time 90 --max-filesize "$2" -o /proc/self/fd/3 -w '%{size_download}' "$1" > "$X/download.count" || code=$?;printf '%s\n' "$code" > "$X/download.status") 3>&1 | head -c "$(( $2+1 ))" > "$3"
  [ "$(cat "$X/download.status")" = 0 ] && [ "$(cat "$X/download.count" | tr -d ' ')" = "$2" ] && [ "$(remote_hash < "$3")" = "$4" ]
 }
 for key in application runtime;do
  name=application;[ "$key" != runtime ] || name=runtime-assets
  download "$(dav_base)/$(field ${key}_path)" "$(field ${key}_size)" "$X/$name.tar.gz" "$(field ${key}_sha256)"
 done
 resource_limit=$(( ( $(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)-$(field protect_kb)-3072)*1024 ))
 [ "$resource_limit" -gt 0 ]
 SC_RECOVERY_RESOURCE_MAX=$resource_limit lua "$X/restore-archive.lua" application "$X/application.tar.gz" "$(field core_sha256)" AX5 "$X/config.original.json" resources > "$X/application.json"
 lua "$X/restore-archive.lua" runtime-assets "$X/runtime-assets.tar.gz" "$(field core_sha256)" AX5 > "$X/runtime.json"
 lua "$X/recovery-session.lua" finalize "$X"
 # Count actual allocated blocks in the isolated staged roots before decoding.
 step=isolated-memory-budget
 need=$(SC_RECOVERY_X=$X lua -e 'local x=os.getenv("SC_RECOVERY_X");local j=require("cjson");local total=2048;for _,n in ipairs({"application","runtime"})do local f=assert(io.open(x.."/"..n..".json"));local a=j.decode(f:read("*a"));f:close();local bytes=n=="application"and a.resource_size or a.unpacked_size;local members=n=="application"and a.resource_members or a.members;total=total+math.ceil(bytes/1024)+members*4 end;print(total)')
 [ "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)" -ge "$(( $(field protect_kb)+need ))" ]
 [ "$(df -Pk /tmp | awk 'END{print $4}')" -ge "$need" ]
 step=isolated-config
 mkdir -p "$X/app" "$X/runtime"
 tar -xzf "$X/runtime-assets.tar.gz" -C "$X/runtime"
 lua "$X/restore-config.lua" "$X"
fi
lua "$X/recovery-session.lua" finalize "$X"
step=ticket-binding
# Regenerate mutable state after all downloads; do not mint for a changed device.
lua "$X/recovery-live.lua" "$profile" "$(remote_fingerprint)" > "$X/current.json"
SC_RECOVERY_X=$X lua -e 'local x=os.getenv("SC_RECOVERY_X");local j=require("cjson");local function read(n)local f=assert(io.open(x.."/"..n));local v=j.decode(f:read("*a"));f:close();return v end;local a,b=read("live.json"),read("current.json");for _,k in ipairs({"config_fingerprint","startup_fingerprint","boot_id","pid","binary_sha256","core_sha256","remote_fingerprint"})do assert(a[k]==b[k],"device changed during preflight")end'
page_enabled=false;[ ! -f "$C/configs/recovery-enabled" ] || page_enabled=true
printf '{"archive_checked":true,"config_checked":true,"core_checked":true,"enabled":%s}\n' "$page_enabled" > "$X/passed.json"
lua "$X/recovery-session.lua" seal "$X"
cp "$X/public.json" "$D/recovery-plan.json.new";mv "$D/recovery-plan.json.new" "$D/recovery-plan.json"
# Keep only small trusted control/evidence files until confirmation expires.
rm -rf "$X/app" "$X/runtime";rm -f "$X/application.tar.gz" "$X/runtime-assets.tar.gz" "$X/config.original.json" "$X/config.check.json"
