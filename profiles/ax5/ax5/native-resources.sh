#!/bin/sh
# Preflight native geodata through the installed ShellCrash source before stopping the proxy.
set -eu
C=/data/ShellCrash
R=/tmp/ShellCrash
file=${1:-$C/configs/config.json}
flags=$(lua - "$file" <<'LUA'
local m=dofile('/data/ShellCrash/ax5/common.lua');local c=m.load(arg[1]);local b=c._native_meta
if not b then return end
local ip,site=false,false
for _,r in ipairs(b.rules or{})do ip=ip or r:match('^GEOIP,')~=nil;site=site or r:match('^GEOSITE,')~=nil end
if ip then print('Country.mmdb:cn_mini.mmdb:1048576')end
if site then print('GeoSite.dat:geosite.dat:8388608')end
LUA
)
[ -n "$flags" ] || exit 0
CRASHDIR=/data/ShellCrash-tool;export CRASHDIR
. "$CRASHDIR/configs/ShellCrash.cfg"
. "$CRASHDIR/libs/web_get_bin.sh"
logger(){ :; }
mkdir -p "$C/ruleset/native"
stage=$R/native-geodata.$$
trap 'rm -f "$stage"' EXIT
fail(){ printf '%s\n' "$1" >&2;exit 1; }
for item in $flags;do
 name=${item%%:*};rest=${item#*:};source=${rest%%:*};max=${rest##*:};path=$C/ruleset/native/$name
 if [ ! -s "$path" ];then
  available=$(awk '/^MemAvailable:/{print $2;found=1} END{if(!found)print 0}' /proc/meminfo)
  [ "$available" -ge "$((max / 1024 + 14336))" ] || fail "模板需要 ${name}，下载内存预算不足；当前配置保留"
  get_bin "$stage" "bin/geodata/$source" >/dev/null 2>&1 || fail "模板需要 ${name}，ShellCrash 工具源下载失败；当前配置保留"
  n=$(wc -c < "$stage");[ "$n" -ge 1024 ] && [ "$n" -le "$max" ] || fail "模板数据库 $name 大小不符合轻量设备限制；当前配置保留"
  free=$(df -k "$C/ruleset/native" | awk 'END{print $4}')
  case "$free" in ''|*[!0-9]*)fail '无法确认数据库剩余空间；当前配置保留';;esac
  [ "$free" -ge "$(((n + 1023) / 1024 + 128))" ] || fail "模板需要 ${name}（${n} 字节），闪存空间不足；当前配置保留"
  cp "$stage" "$path.new" || { rm -f "$path.new";fail "模板数据库 $name 写入失败；当前配置保留"; }
  mv "$path.new" "$path"
  rm -f "$stage"
 fi
 cp "$path" "$R/$name"
done
