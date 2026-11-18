#!/bin/sh
# Sourced in the existing configuration transaction, never eval subscription data.
native_pin_url(){
 pin_url=$1;pin_stage=$2
 case "$pin_url" in https://raw.githubusercontent.com/*)
  rest=${pin_url#https://raw.githubusercontent.com/};owner=${rest%%/*};rest=${rest#*/};repo=${rest%%/*};rest=${rest#*/};ref=${rest%%/*};path=${rest#*/}
  if ! printf '%s' "$ref"|grep -Eq '^[a-f0-9]{40}$';then
   if printf '%s/%s/%s' "$owner" "$repo" "$ref"|grep -Eq '^[A-Za-z0-9._/-]+$';then
    curl -4 --noproxy '*' -fsSG --connect-timeout 3 --max-time 8 --max-filesize 65536 --data-urlencode "path=$path" --data-urlencode "sha=$ref" --data-urlencode 'per_page=1' "https://api.github.com/repos/$owner/$repo/commits" > "$pin_stage/commit.json" 2>/dev/null || :
    commit=$(sed -n 's/.*"sha": *"\([a-f0-9]\{40\}\)".*/\1/p' "$pin_stage/commit.json"|head -1)
    [ -z "$commit" ] || pin_url="https://raw.githubusercontent.com/$owner/$repo/$commit/$path"
   fi
  fi;;esac
 printf '%s' "$pin_url"
}
native_resources_backup(){
 . "$C/starts/remote.sh"
 remote_ready || return 0
 [ "$(remote_transport)" = webdav ] || return 0
 while IFS="$(printf '\t')" read -r index format url sha;do
  ext=srs;[ "$format" != source ] || ext=json
  if ! remote_put rules "/tmp/ShellCrash/ruleset/native-$sha.$ext" "$ext" >/dev/null;then
   date +%s > "$C/configs/mirror.pending";echo "规则资源 $index 远端备份未完成，本机配置继续使用" >&2
  fi
 done < "$C/configs/native-resources.tsv"
}
native_clean_cache(){
 for file in /tmp/ShellCrash/ruleset/native-*;do
  [ -f "$file" ] || continue;name=${file##*/};hash=${name#native-};hash=${hash%.*}
  printf '%s' "$hash"|grep -Eq '^[a-f0-9]{64}$' || continue
  grep -q "$hash$" "$C/configs/native-resources.tsv" 2>/dev/null || rm -f "$file"
 done
}
native_dataset_key(){
 # Versions of the same GitHub dataset can fall back to the previously
 # installed version. Other URLs are not treated as interchangeable.
 case "$1" in https://raw.githubusercontent.com/*)
  rest=${1#https://raw.githubusercontent.com/};owner=${rest%%/*};rest=${rest#*/};repo=${rest%%/*};rest=${rest#*/};path=${rest#*/}
  printf '%s/%s/%s' "$owner" "$repo" "$path";;
 *)return 1;;esac
}
# The same source/CDN/proxy ordering is used by both device adapters.
. "$C/starts/rule-source.sh"
rule_validation_binary()(
 pid=$(pidof CrashCore | awk '{print $1}')
 if [ -n "$pid" ] && [ -x "/proc/$pid/exe" ];then printf '/proc/%s/exe\n' "$pid";return;fi
 binary=/tmp/ShellCrash/CrashCore
 if [ ! -x "$binary" ];then
  archive=/tmp/ShellCrash/CrashCore.tar.gz
  expected_core=$(sed -n 's/^sha256=//p' "$C/configs/core-installed.info")
  printf '%s' "$expected_core" | grep -Eq '^[a-f0-9]{64}$' || return 1
  echo "$expected_core  $archive" | sha256sum -c - >/dev/null 2>&1 || return 1
  [ "$(tar -tzf "$archive")" = CrashCore ] || return 1
  bytes=$(tar -ztvf "$archive" | awk '{print $3}')
  case "$bytes" in ''|*[!0-9]*)return 1;;esac
  [ "$bytes" -le 33554432 ] || return 1
  available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  [ "${available:-0}" -ge "$(( (bytes+1023)/1024+${rh_protect_mb:-12}*1024 ))" ] || return 1
  tar -zxf "$archive" -C /tmp/ShellCrash || return 1
  chmod 700 "$binary" || return 1
  # The exact archive is verified and materialized; release its duplicate RAM.
  rm -f "$archive"
 fi
 printf '%s\n' "$binary"
)
rule_source_validate(){
 binary=$(rule_validation_binary) || return 1
 available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
 [ "${available:-0}" -ge "$(( (${rh_protect_mb:-12}+8)*1024 ))" ] || return 1
 case "$format" in
  binary)GOMEMLIMIT=8MiB GOGC=10 "$binary" rule-set decompile --output /dev/null "$1" >/dev/null 2>&1;;
  source)GOMEMLIMIT=8MiB GOGC=10 "$binary" rule-set compile --output /dev/null "$1" >/dev/null 2>&1;;
  *)return 1;;
 esac
}
native_resource_fetch(){ rule_source_fetch "$1" "$2" "$3" 524288 "${4:-0}"; }
native_resources_prepare()(
 input=$1;candidate=$2;manifest=$3;allow_latest=${4:-0}
 stage="$D/native-resources.$$"
 (umask 077;mkdir "$stage") || return 1
 mkdir -p /tmp/ShellCrash/ruleset || { rmdir "$stage";return 1; }
 trap 'rm -rf "$stage"' EXIT
 : > "$manifest";rm -f "$D/native-resource-retained";count=0;total=0
 [ "$(wc -c < "$input")" -le 49152 ] || return 1
 while IFS="$(printf '\t')" read -r index format url expected || [ -n "$url" ];do
  count=$((count+1));[ "$count" -le 16 ] || return 1
  printf '%s' "$index" | grep -Eq '^(0|[1-9]|1[0-5])$' || return 1
  case "$format" in binary)ext=srs;;source)ext=json;;*)return 1;;esac
  [ "${#url}" -le 2048 ] && printf '%s' "$url" | grep -Eq '^https?://[^/@[:space:]]+(/[^[:space:]]*)?$' || return 1
  case "$expected" in '') :;;*)printf '%s' "$expected"|grep -Eq '^[a-f0-9]{64}$'||return 1;;esac
  if [ -z "$expected" ];then
   # Reuse only an exact immutable GitHub commit already validated in the
   # installed manifest. Mutable URLs never gain trust merely by matching.
   url=$(native_pin_url "$url" "$stage")
   case "$url" in https://raw.githubusercontent.com/*)
    rest=${url#https://raw.githubusercontent.com/};rest=${rest#*/};rest=${rest#*/};ref=${rest%%/*}
    if printf '%s' "$ref"|grep -Eq '^[a-f0-9]{40}$' && [ -s "$C/configs/native-resources.tsv" ];then
     while IFS="$(printf '\t')" read -r old_index old_format old_url old_sha;do
      [ "$old_format" = "$format" ] && [ "$old_url" = "$url" ] || continue
      printf '%s' "$old_sha"|grep -Eq '^[a-f0-9]{64}$' || continue
      prior="/tmp/ShellCrash/ruleset/native-$old_sha.$ext"
      [ -f "$prior" ] && echo "$old_sha  $prior"|sha256sum -c - >/dev/null 2>&1 || continue
      expected=$old_sha;break
     done < "$C/configs/native-resources.tsv"
    fi;;esac
  fi
  asset="/tmp/ShellCrash/ruleset/native-$expected.$ext"
  if [ -n "$expected" ] && [ -f "$asset" ] && echo "$expected  $asset"|sha256sum -c - >/dev/null 2>&1;then :
  else
   available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
   # Each fetch is bounded to 512 KB; reserve another 512 KB for curl and shell,
   # in addition to the configured protection floor. Earlier assets are already
   # reflected in MemAvailable; do not budget the entire 2 MB again.
   required=$(( (${rh_protect_mb:-12}+1)*1024 ))
   [ "${available:-0}" -ge "$(( ${rh_protect_mb:-12}*1024 ))" ] || { echo '规则资源暂存内存不足，当前配置保留' >&2;return 1; }
   retained=0
   if [ "${available:-0}" -lt "$required" ] && [ -z "$expected" ] && [ -s "$C/configs/native-resources.tsv" ];then
    key=$(native_dataset_key "$url") || key=''
    if [ -n "$key" ];then
     while IFS="$(printf '\t')" read -r old_index old_format old_url old_sha;do
      [ "$old_format" = "$format" ] && [ "$(native_dataset_key "$old_url")" = "$key" ] || continue
      printf '%s' "$old_sha"|grep -Eq '^[a-f0-9]{64}$' || continue
      prior="/tmp/ShellCrash/ruleset/native-$old_sha.$ext"
      [ -f "$prior" ] && echo "$old_sha  $prior"|sha256sum -c - >/dev/null 2>&1 || continue
      expected=$old_sha;asset=$prior;url=$old_url;retained=1
      printf '%s\n' "$index" >> "$D/native-resource-retained"
      echo "规则资源 $index 沿用此前已校验版本；内存不足，本次未更新规则集" >&2
      break
     done < "$C/configs/native-resources.tsv"
    fi
   fi
   if [ "$retained" != 1 ];then
   [ "${available:-0}" -ge "$required" ] || { echo '规则资源暂存内存不足，当前配置保留' >&2;return 1; }
   next="$stage/$index.$ext"
   . "$C/starts/remote.sh"
   fetched=0
   if [ -n "$expected" ] && remote_ready && [ "$(remote_transport)" = webdav ];then
    remote_fetch rules "$expected" "$ext" "$next" 524288 && fetched=1
   fi
   if [ "$fetched" = 0 ];then
    native_resource_fetch "$url" "$next" "$expected" "$allow_latest" || { echo "规则资源 $index 获取失败；需恢复同版本规则缓存或检查直连下载" >&2;return 1; }
   fi
   available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
   [ "${available:-0}" -ge "$(( ${rh_protect_mb:-12}*1024 ))" ] || { echo '规则资源暂存内存不足，当前配置保留' >&2;return 1; }
   size=$(wc -c < "$next");[ "$size" -gt 0 ] && [ "$size" -le 524288 ] || return 1
   sha=$(sha256sum "$next"|awk '{print $1}')
   if [ -f "$next.updated" ];then
    [ "$sha" = "$(cat "$next.updated")" ] || return 1
    if [ -n "$candidate" ] && [ -n "$expected" ];then
     sed "s|/tmp/ShellCrash/ruleset/native-$expected.$ext|/tmp/ShellCrash/ruleset/native-$sha.$ext|g" "$candidate" > "$candidate.resource" || return 1
     mv "$candidate.resource" "$candidate" || return 1
    fi
    expected=$sha
   fi
   [ -z "$expected" ] || [ "$sha" = "$expected" ] || { echo "规则资源 $index 与保存版本不一致" >&2;return 1; }
   expected=$sha;asset="/tmp/ShellCrash/ruleset/native-$expected.$ext"
   mv "$next" "$asset" || return 1
   fi
  fi
  total=$((total+$(wc -c < "$asset")));[ "$total" -le 2097152 ] || { echo '订阅规则资源超过 K2P 的 2 MB 上限，请使用精简模板' >&2;return 1; }
  printf '%s\t%s\t%s\t%s\n' "$index" "$format" "$url" "$expected" >> "$manifest"
  if [ -n "$candidate" ];then
   sed "s|\"@@rs-$index@@\"|\"$asset\"|g" "$candidate" > "$candidate.resource" || return 1
   mv "$candidate.resource" "$candidate" || return 1
  fi
 done < "$input"
)

native_resources_recover()(
 work="$D/native-recovery.$$";mkdir "$work" || return 1
 trap 'rm -rf "$work"' EXIT
 cp "$C/jsons/config.json" "$work/config.before" || return 1
 cp "$work/config.before" "$work/config.next" || return 1
 cp "$C/configs/native-resources.tsv" "$work/manifest.before" || return 1
 native_resources_prepare "$work/manifest.before" "$work/config.next" "$work/manifest.next" 1 || return 1
 before=$(sha256sum "$work/manifest.before" | awk '{print $1}')
 [ "$before" != "$(sha256sum "$work/manifest.next" | awk '{print $1}')" ] || return 0
 # A new digest is committed only with a complete configuration check.
 binary=$(rule_validation_binary) || return 1
 GOMEMLIMIT=8MiB GOGC=10 "$binary" check -D /tmp/ShellCrash -c "$work/config.next" > "$work/check.log" 2>&1 || { cat "$work/check.log" >&2;return 1; }
 [ "$before" = "$(sha256sum "$C/configs/native-resources.tsv" | awk '{print $1}')" ] || return 1
 echo "$(sha256sum "$work/config.before" | awk '{print $1}')  $C/jsons/config.json" | sha256sum -c - >/dev/null 2>&1 || return 1
 cp "$work/config.next" "$C/jsons/config.json.new" && mv "$C/jsons/config.json.new" "$C/jsons/config.json" || return 1
 cp "$work/manifest.next" "$C/configs/native-resources.tsv.new" && mv "$C/configs/native-resources.tsv.new" "$C/configs/native-resources.tsv" || { cp "$work/config.before" "$C/jsons/config.json";return 1; }
 recover_save(){
  attempts=0
  while :;do
   rc=0;SC_STORAGE_MAX_BYTES=499712 SC_STORAGE_VERIFY=1 "$C/starts/save_storage.sh" && return 0 || rc=$?
   [ "$rc" = 75 ] && [ "$attempts" -lt 3 ] || return "$rc"
   attempts=$((attempts+1));sleep 2
  done
 }
 if ! recover_save;then
  cp "$work/config.before" "$C/jsons/config.json";cp "$work/manifest.before" "$C/configs/native-resources.tsv"
  recover_save || echo '规则恢复保存失败，原版本回写也未确认；请检查Storage' >&2
  return 1
 fi
 logger -t ShellCrash 'Old rule assets unavailable; latest compatible rules checked and committed'
 native_resources_backup || :
)

native_profile_candidate(){
 input=$1
 [ "$(grep -c '^"outbounds":\[' "$input")" = 1 ] && [ "$(grep -c '^"route":{' "$input")" = 1 ] || return 1
 for field in resources policy;do
  value=$(sed -n "s/^\"_panel_${field}_b64\":\"\([A-Za-z0-9+/=]*\)\",\{0,1\}$/\1/p" "$input")
  printf '%s' "$value"|base64 -d > "$D/native-$field.input" 2>/dev/null || return 1
 done
 [ "$(wc -c < "$D/native-policy.input")" -le 12000 ] || return 1
 awk 'FNR==NR{if(/^"outbounds":/){o=$0;sub(/,$/,"",o)}if(/^"route":/){r=$0;sub(/,$/,"",r)}next}/^"outbounds":/{print o ",";next}/^"route":/{print r ",";next}{print}' "$input" "$C/jsons/config.json" > "$D/candidate.json" || return 1
 native_resources_prepare "$D/native-resources.input" "$D/candidate.json" "$D/native-resources.tsv" || return 1
 : > "$D/native-policy.rules"
 awk -v input="$D/native-policy.input" -v oldfile="$C/configs/policy.rules" -v metadata="$D/native-policy.tsv" -v compiled="$D/native-policy.rules" -f "$C/starts/policy_merge.awk" "$D/candidate.json" > "$D/native-merged.json" || return 1
 [ -f "$D/native-policy.tsv" ] || : > "$D/native-policy.tsv"
 mv "$D/native-merged.json" "$D/candidate.json"
}
