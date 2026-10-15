#!/bin/sh
# On-demand, read-only K2P same-core preflight. Called with a server-generated
# plan; no service stop, Storage write, credential export or resident worker.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH GOMEMLIMIT=12MiB GOGC=25
set -eu
umask 077
X=${1:-}
case "$X" in /tmp/sc-preflight-????????) :;;*)exit 2;;esac
id=${X##*-};case "$id" in *[!a-f0-9]*)exit 2;;esac
C=/etc/storage/ShellCrash;D=/tmp/sc-admin
field(){ sed -n "s/^$1=//p" "$X/plan" | head -1; }
reject(){ echo "$1" >&2;exit 1; }
hash(){ sha256sum "$1" | awk '{print $1}'; }
rm -f "$X/result.json"
[ "$(uname -m)" = mips ] || reject 'unsupported architecture'
for key in remote_fingerprint core_sha256 binary_sha256 application_sha256 runtime_sha256;do
 value=$(field "$key");[ "${#value}" = 64 ] || reject 'invalid hash';case "$value" in *[!a-f0-9]*)reject 'invalid hash';;esac
done
for key in application_size runtime_size protect_kb;do
 value=$(field "$key");case "$value" in ''|*[!0-9]*)reject 'invalid resource budget';;esac
 [ "${#value}" -le 8 ] || reject 'resource budget exceeds limit'
done
[ "$(field application_size)" -gt 0 ] && [ "$(field application_size)" -le 4000000 ] || reject 'application exceeds limit'
[ "$(field runtime_size)" -gt 0 ] && [ "$(field runtime_size)" -le 4000000 ] || reject 'runtime exceeds limit'
protect=$(field protect_kb);[ "$protect" -ge 12288 ] && [ "$protect" -le 65536 ] || reject 'invalid memory protection'
for key in application_path runtime_path;do
 value=$(field "$key")
 printf '%s' "$value" | LC_ALL=C grep -Eq '^(backups|objects|imports|baselines|recoveries)/[A-Za-z0-9_./-]+$' || reject 'invalid component path'
 case "/$value/" in *'/../'*|*'/./'*|*'//'*)reject 'invalid component path';;esac
done
# Never treat a browser/PC-supplied core record as authoritative.
. "$C/starts/core_release.sh"
release_valid "$C/configs/core-installed.info" || reject 'invalid installed core record'
[ "$(release_get sha256 "$C/configs/core-installed.info")" = "$(field core_sha256)" ] || reject 'cross-version recovery is unsupported'
[ "$(release_get version "$C/configs/core-installed.info")" = "$(field core_version)" ] || reject 'cross-version recovery is unsupported'
[ "$(release_get arch "$C/configs/core-installed.info")" = mipsle-softfloat ] || reject 'unsupported core architecture'
pid=$(pidof CrashCore);case "$pid" in ''|*[!0-9]*)reject 'a single running core is required';;esac
[ "$(hash "/proc/$pid/exe")" = "$(field binary_sha256)" ] || reject 'running core changed'
# Bind mutable local inputs for the later confirmation supervisor as well.
current_fingerprint(){
 { sha256sum "$C/configs/core-installed.info" "$C/configs/ShellCrash.cfg" "$C/jsons/config.json";[ -f "$C/.dis_startup" ] && echo startup=0 || echo startup=1;[ -f "$C/configs/panel-disabled" ] && echo enabled=0 || echo enabled=1; } | sha256sum | awk '{print $1}'
}
initial_config=$(current_fingerprint)
. "$C/starts/remote.sh"
[ "$(remote_transport)" = webdav ] && [ "$(remote_fingerprint)" = "$(field remote_fingerprint)" ] || reject 'remote identity changed'
remote_transfer_ready || reject 'WebDAV is unavailable'
compressed_kb=$((($(field application_size)+$(field runtime_size)+1023)/1024))
[ "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)" -ge "$((protect+compressed_kb+3072))" ] || reject 'insufficient memory'
[ "$(df -Pk /tmp | awk 'END{print $4}')" -ge "$((compressed_kb+3072))" ] || reject 'insufficient tmpfs space'
# The firmware curl may only enforce --max-filesize for announced lengths.
# Also bound the actual body; no FIFO or large core archive is needed.
download(){
 (code=0;dav_curl --fail --max-time 90 --max-filesize "$2" -o /proc/self/fd/3 -w '%{size_download}' "$1" > "$X/download.count" || code=$?;printf '%s\n' "$code" > "$X/download.status") 3>&1 | head -c "$(( $2+1 ))" > "$3"
 [ "$(cat "$X/download.status")" = 0 ] && [ "$(cat "$X/download.count" | tr -d ' ')" = "$2" ]
}
# Downloads are bounded and verified before the Lua archive validator sees them.
for key in application runtime;do
 name=application;[ "$key" != runtime ] || name=runtime-assets
 download "$(dav_base)/$(field ${key}_path)" "$(field ${key}_size)" "$X/$name.tar.gz" || reject 'component download failed'
 [ "$(wc -c < "$X/$name.tar.gz" | tr -d ' ')" = "$(field ${key}_size)" ] && [ "$(hash "$X/$name.tar.gz")" = "$(field ${key}_sha256)" ] || reject 'component hash or size mismatch'
done
lua "$X/restore-archive.lua" application "$X/application.tar.gz" "$(field core_sha256)" K2P "$X/config.original.json" > "$X/application.json"
lua "$X/restore-archive.lua" runtime-assets "$X/runtime-assets.tar.gz" "$(field core_sha256)" K2P > "$X/runtime.json"
# tar can use one tmpfs block per small member; account for member overhead as
# well as payload and the two configuration copies before any extraction.
need=$(SC_PREFLIGHT_METADATA="$X/runtime.json" lua -e 'local j=require("cjson");local f=assert(io.open(os.getenv("SC_PREFLIGHT_METADATA")));local r=j.decode(f:read("*a"));f:close();print(math.ceil(r.unpacked_size/1024)+r.members*4+4096)')
[ "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)" -ge "$((protect+need))" ] || reject 'insufficient memory for isolated check'
[ "$(df -Pk /tmp | awk 'END{print $4}')" -ge "$need" ] || reject 'insufficient tmpfs space'
# Only a validated runtime archive is extracted, within this private directory.
mkdir "$X/runtime"
tar -xzf "$X/runtime-assets.tar.gz" -C "$X/runtime"
lua "$X/restore-config.lua" "$X"
/proc/"$pid"/exe check -D "$X/runtime/ShellCrash" -c "$X/config.check.json" > "$X/core-check.log" 2>&1 || reject 'configuration is incompatible with the installed core'
[ "$(pidof CrashCore)" = "$pid" ] && [ "$(hash "/proc/$pid/exe")" = "$(field binary_sha256)" ] || reject 'running core changed during preflight'
SC_PREFLIGHT_METADATA="$X/application.json" SC_PREFLIGHT_CORE_VERSION=$(field core_version) lua -e 'local j=require("cjson");local f=assert(io.open(os.getenv("SC_PREFLIGHT_METADATA")));local a=j.decode(f:read("*a"));f:close();assert(a.core_version==os.getenv("SC_PREFLIGHT_CORE_VERSION"),"internal core version mismatch")'
[ "$(current_fingerprint)" = "$initial_config" ] && [ "$(remote_fingerprint)" = "$(field remote_fingerprint)" ] || reject 'local configuration or remote identity changed during preflight'
printf '{"archive_checked":true,"config_checked":true,"executor_ready":false,"pid":%s,"live_fingerprint":"%s"}\n' "$pid" "$initial_config" > "$X/result.json"
echo 'Native archives and isolated configuration passed; no restore performed'
