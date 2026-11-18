#!/bin/sh
# Restore the current core's CN file before its normal full configuration check.
set -eu
C=/data/ShellCrash;R=/tmp/ShellCrash;D=$R
. "$C/ax5/rule-source.sh"
kind=$1
case "$kind" in meta)ext=mrs;;singbox)ext=srs;;*)exit 2;;esac
path=$C/ruleset/cn.$ext
metadata=$C/configs/domain-$kind.json
expected=$(lua - "$metadata" <<'LUA'
local m=dofile('/data/ShellCrash/ax5/common.lua');local s=m.load(arg[1]);if type(s)=='table'and type(s.sha256)=='string'and s.sha256:match('^[a-f0-9]+$')and #s.sha256==64 then print(s.sha256)end
LUA
)
# Existing trusted data is kept; metadata makes its WebDAV object recoverable.
if [ -s "$path" ] && { [ -z "$expected" ] || [ "$(rule_source_digest "$path")" = "$expected" ]; };then
 if [ -z "$expected" ];then
  sha=$(rule_source_digest "$path")
  printf '{"kind":"%s","file":"cn.%s","sha256":"%s","updated":%s}\n' "$kind" "$ext" "$sha" "$(date +%s)" > "$metadata.new"
  mv "$metadata.new" "$metadata"
 fi
 exit 0
fi
available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
[ "${available:-0}" -ge 22528 ] || { echo '规则恢复内存预算不足' >&2;exit 1; }
. "$C/ax5/remote.sh"
stage=$R/domain-candidate.$ext
trap 'rm -f "$stage" "$R/domain-source"' EXIT
obtained=0
if [ -n "$expected" ] && remote_fetch cn "$expected" "$ext" "$stage" 2000000;then obtained=1;fi
if [ "$obtained" = 0 ];then "$C/ax5/database-source.sh" "$kind";fi
size=$(wc -c < "$stage");[ "$size" -gt 1024 ] && [ "$size" -lt 2000000 ] || exit 1
if [ "$kind" = singbox ];then
 GOMEMLIMIT=8MiB GOGC=10 "$R/CrashCore" rule-set decompile --output /dev/null "$stage" || exit 1
else
 preview=$R/rule-recovery.yaml
 trap 'rm -f "$stage" "$R/domain-source" "$preview"' EXIT
 printf 'mode: rule\nlog-level: silent\nrule-providers:\n  cn:\n    type: file\n    behavior: domain\n    format: mrs\n    path: %s\nrules:\n  - RULE-SET,cn,DIRECT\n  - MATCH,DIRECT\n' "$stage" > "$preview"
 "$C/ax5/check-binary.sh" meta "$R/CrashCore" -t -d "$R" -f "$preview" || exit 1
fi
free=$(df -k "$C/ruleset" | awk 'END{print $4}')
case "$free" in ''|*[!0-9]*)exit 1;;esac
[ "$free" -ge "$(((size+1023)/1024+128))" ] || exit 1
sha=$(rule_source_digest "$stage")
cp "$stage" "$path.new" && mv "$path.new" "$path" || exit 1
printf '{"kind":"%s","file":"cn.%s","sha256":"%s","updated":%s}\n' "$kind" "$ext" "$sha" "$(date +%s)" > "$metadata.new"
mv "$metadata.new" "$metadata"
sync
logger -t ShellCrash 'CN rules restored; same-source latest compatible version allowed after cache failure'
