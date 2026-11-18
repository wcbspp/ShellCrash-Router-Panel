#!/bin/sh
# Shared download policy; adapters validate native rule formats before accepting a new digest.
rule_source_digest(){
 if type sha256sum >/dev/null 2>&1;then
  digest=$(sha256sum "$1") || return 1
  digest=${digest%% *}
 else
  digest=$(openssl dgst -sha256 "$1") || return 1
  digest=${digest##* }
 fi
 printf '%s\n' "$digest" | grep -Eq '^[a-f0-9]{64}$' || return 1
 printf '%s\n' "$digest"
}
rule_source_latest_url(){
 case "$1" in
  https://raw.githubusercontent.com/SagerNet/sing-geosite/*|https://raw.githubusercontent.com/SagerNet/sing-geoip/*)
   rest=${1#https://raw.githubusercontent.com/};owner=${rest%%/*};rest=${rest#*/};repo=${rest%%/*};rest=${rest#*/};path=${rest#*/}
   printf 'https://raw.githubusercontent.com/%s/%s/rule-set/%s\n' "$owner" "$repo" "$path";;
  *)printf '%s\n' "$1";;
 esac
}
rule_source_transfer()(
 transfer_max=$1;transfer_file=$2;shift 2
 trap 'rm -f "$transfer_file.status"' EXIT
 (rc=0;curl "$@" -o - || rc=$?;printf '%s\n' "$rc" > "$transfer_file.status") | head -c "$((transfer_max+1))" > "$transfer_file"
 if [ "$(cat "$transfer_file.status")" = 0 ] && [ -s "$transfer_file" ] && [ "$(wc -c < "$transfer_file")" -le "$transfer_max" ];then return 0;fi
 rm -f "$transfer_file";return 1
)
rule_source_fetch()(
 resource_url=$1;resource_next=$2;resource_sha=$3;resource_max=${4:-524288};resource_latest=${5:-0};resource_cdn=''
 rm -f "$resource_next.updated" "$resource_next.latest"
 trap 'rm -f "$resource_next.latest"' EXIT
 case "$resource_url" in https://raw.githubusercontent.com/*)
  resource_rest=${resource_url#https://raw.githubusercontent.com/}
  if printf '%s' "$resource_rest" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+$';then
   resource_owner=${resource_rest%%/*};resource_rest=${resource_rest#*/}
   resource_repo=${resource_rest%%/*};resource_rest=${resource_rest#*/}
   resource_ref=${resource_rest%%/*};resource_path=${resource_rest#*/}
   resource_cdn="https://testingcf.jsdelivr.net/gh/$resource_owner/$resource_repo@$resource_ref/$resource_path"
  fi;;esac
 ca="$C/configs/subscription-ca.pem";tls='';[ ! -s "$ca" ] || tls="--cacert $ca"
 # A mirror changes transport only; never substitute another dataset/version.
 for resource_source in "$resource_url" "$resource_cdn";do
  [ -n "$resource_source" ] || continue
  if rule_source_transfer "$resource_max" "$resource_next" -q -4 $tls --noproxy '*' -fsSL --connect-timeout 4 --max-time 20 --max-filesize "$resource_max" "$resource_source";then
   [ -z "$resource_sha" ] || [ "$(rule_source_digest "$resource_next")" = "$resource_sha" ] || {
    if [ "$resource_latest" = 1 ] && [ ! -s "$resource_next.latest" ];then mv "$resource_next" "$resource_next.latest" || return 1;fi
    continue
   }
   if [ -z "$resource_sha" ] && [ "$resource_latest" = 1 ];then rule_source_validate "$resource_next" || continue;fi
   return 0
  fi
 done
 # Cold boot must not depend on the core that these rules are needed to start.
 if pidof CrashCore >/dev/null 2>&1 && netstat -lnt 2>/dev/null | awk '$4 ~ /:7890$/ {ready=1} END{exit !ready}';then
  if rule_source_transfer "$resource_max" "$resource_next" -q -4 $tls --noproxy '' --proxy "http://${PANEL_LAN_IP:-127.0.0.1}:7890" -fsSL --connect-timeout 4 --max-time 20 --max-filesize "$resource_max" "$resource_url";then
   if [ -z "$resource_sha" ];then
    if [ "$resource_latest" != 1 ] || rule_source_validate "$resource_next";then return 0;fi
   elif [ "$(rule_source_digest "$resource_next")" = "$resource_sha" ];then return 0;fi
   if [ "$resource_latest" = 1 ] && [ ! -s "$resource_next.latest" ];then mv "$resource_next" "$resource_next.latest" || return 1;fi
  fi
 fi
 if [ "$resource_latest" = 1 ] && [ ! -s "$resource_next.latest" ];then
  newest=$(rule_source_latest_url "$resource_url")
  if [ "$newest" != "$resource_url" ];then
   rule_source_fetch "$newest" "$resource_next.latest" '' "$resource_max" 0 || rm -f "$resource_next.latest"
  fi
 fi
 if [ "$resource_latest" = 1 ] && [ -s "$resource_next.latest" ];then
  resource_size=$(wc -c < "$resource_next.latest")
  [ "$resource_size" -le "$resource_max" ] && rule_source_validate "$resource_next.latest" || return 1
  mv "$resource_next.latest" "$resource_next" || return 1
  rule_source_digest "$resource_next" > "$resource_next.updated" || return 1
  echo '原规则版本不可用，已校验同源最新兼容版本' >&2
  return 0
 fi
 echo '规则直连获取未成功；未就绪的本机代理不会作为启动依赖' >&2
 return 1
)
