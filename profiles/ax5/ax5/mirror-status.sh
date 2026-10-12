#!/bin/sh
set -eu
. /data/ShellCrash/ax5/core-env.sh
kind=${1:-$KIND}
case "$kind" in meta|singbox) :;; *) exit 2;; esac
if ! remote_ready;then printf '{"configured":false,"available":false}\n' > "$R/mirror-check.json";exit 0;fi
file=$R/mirror-info.tmp
if remote_manifest "$kind" > "$file";then :
elif [ -n "$MIRROR" ] && curl -4 --noproxy '*' -fsSL --connect-timeout 3 --max-time 6 --max-filesize 2048 "$MIRROR/$kind-info.txt" -o "$file";then :
else rm -f "$file";fi
if [ -s "$file" ];then
 v=$(sed -n 's/^VERSION=//p' "$file");h=$(sed -n 's/^HASH=//p' "$file");k=$(sed -n 's/^KIND=//p' "$file")
 if [ "$k" = "$kind" ] && printf '%s' "$v" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$' && printf '%s' "$h" | grep -Eq '^[a-f0-9]{64}$';then
  printf '{"configured":true,"available":true,"kind":"%s","version":"%s","sha256":"%s","checked":%s}\n' "$k" "$v" "$h" "$(date +%s)" > "$R/mirror-check.json";rm -f "$file";exit 0
 fi
fi
printf '{"configured":true,"available":false,"kind":"%s","checked":%s}\n' "$kind" "$(date +%s)" > "$R/mirror-check.json"
rm -f "$file"
