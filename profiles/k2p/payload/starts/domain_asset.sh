#!/bin/sh
# Small fixed DNS rule asset; no persistent copy in K2P Storage.
domain_asset_valid(){ printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null 2>&1; }
domain_asset_expected(){
 domain_hash=$1;domain_source='';domain_source_type=direct
 domain_record="$C/configs/domain-installed.info"
 [ -e "$domain_record" ] || return 0
 [ -s "$domain_record" ] && [ "$(wc -c < "$domain_record")" -le 2048 ] || return 1
 awk -F= '$1!~/^(sha256|size|url|type|updated)$/||++seen[$1]>1{bad=1}END{exit bad||seen["sha256"]!=1||seen["url"]!=1||seen["type"]!=1}' "$domain_record" || return 1
 domain_hash=$(sed -n 's/^sha256=//p' "$domain_record")
 domain_source=$(sed -n 's/^url=//p' "$domain_record")
 domain_source_type=$(sed -n 's/^type=//p' "$domain_record")
 printf '%s' "$domain_hash" | grep -Eq '^[a-f0-9]{64}$' || return 1
 case "$domain_source_type" in direct|archive) :;;*)return 1;;esac
 case "$domain_source" in https://*) :;;*)return 1;;esac
 # Metadata is data, never sourced or evaluated. Reject ambiguous lines.
 [ "${#domain_source}" -le 1508 ] && printf '%s' "$domain_source" | grep -Eq '^https://[A-Za-z0-9._~:/%+?=&@,-]+$'
}
domain_asset_commit(){
 committed_file=$1;committed_source=$2;committed_type=$3
 size=$(wc -c < "$committed_file")
 [ "$size" -gt 1024 ] && [ "$size" -le 1048576 ] || return 1
 [ "${#committed_source}" -le 1508 ] && printf '%s' "$committed_source" | grep -Eq '^https://[A-Za-z0-9._~:/%+?=&@,-]+$' || return 1
 case "$committed_type" in direct|archive) :;;*)return 1;;esac
 . "$C/starts/resource_health.sh";resource_read
 [ "$rh_available" -ge "$((rh_protect_mb*1024+6144))" ] || { echo '内存不足以安全保存新域名库记录';return 1; }
 binary=/tmp/ShellCrash/CrashCore
 pid=$(pidof CrashCore | awk '{print $1}');[ -z "$pid" ] || binary=/proc/$pid/exe
 GOMEMLIMIT=8MiB GOGC=10 "$binary" rule-set decompile --output /dev/null "$committed_file" >/dev/null 2>&1 || { echo '域名库格式校验失败';return 1; }
 record="$C/configs/domain-installed.info";old="$D/domain-record.before"
 had_old=0;[ ! -f "$record" ] || { cp "$record" "$old";had_old=1; }
 digest=$(sha256sum "$committed_file" | awk '{print $1}')
 printf 'sha256=%s\nsize=%s\nurl=%s\ntype=%s\nupdated=%s\n' "$digest" "$size" "$committed_source" "$committed_type" "$(date +%s)" > "$record.new"
 mv "$record.new" "$record" || return 1
 if ! "$C/starts/save_storage.sh";then
  if [ "$had_old" = 1 ];then cp "$old" "$record";else rm -f "$record";fi
  echo '新域名库记录未能持久保存，更新不生效';return 1
 fi
 rm -f "$old"
 . "$C/starts/mirror_lib.sh";domain_hash=$digest;domain_file=$committed_file;domain_asset_sync
 echo '域名库已校验并保存版本记录，重启继续使用该版本'
}
domain_asset_sync(){
 remote_ready || return 0
 if ! remote_has cn "$domain_hash" srs;then
  remote_put cn "$domain_file" srs >/dev/null || {
   logger -t ShellCrash 'Domain database ready locally; remote synchronization pending'
   return 0
  }
 fi
}
domain_asset_ensure(){
 domain_file=$2;domain_work=$3
 domain_asset_expected "$1" || { logger -t ShellCrash 'Saved domain version record invalid; refusing implicit downgrade';return 1; }
 if domain_asset_valid "$domain_hash" "$domain_file";then return 0;fi
 . "$C/starts/mirror_lib.sh"
 # Disabled or unverified settings never connect. The remote object must match
 # the exact expected digest; an application backup alone is not this cache.
 if remote_fetch cn "$domain_hash" srs "$domain_work/cn.new" 1048576 && domain_asset_valid "$domain_hash" "$domain_work/cn.new";then
  mv "$domain_work/cn.new" "$domain_file" || return 1
  logger -t ShellCrash 'Domain database restored from verified remote cache'
  return 0
 fi
 { for cert in /etc/ssl/certs/*.crt;do [ ! -f "$cert" ] || cat "$cert";done;cat "$C/configs/subscription-ca.pem"; } > "$domain_work/ca.pem"
 domain_base=$(mirror_base);domain_custom='';[ -z "$domain_base" ] || domain_custom="$domain_base/cn-$domain_hash.srs"
 domain_found=0
 for domain_url in $domain_source $domain_custom ${PANEL_CN_MIRROR:-} https://raw.githubusercontent.com/DustinWin/ruleset_geodata/877462de3ab7fe81ad4b8bd0f7d4a8fd9df363fe/cn.srs https://testingcf.jsdelivr.net/gh/DustinWin/ruleset_geodata@877462de3ab7fe81ad4b8bd0f7d4a8fd9df363fe/cn.srs;do
  if [ "$domain_source_type" = archive ] && [ "$domain_url" = "$domain_source" ];then
   if curl --cacert "$domain_work/ca.pem" --noproxy '*' -fsSL --connect-timeout 10 --max-time 40 --max-filesize 2097152 "$domain_url" -o "$domain_work/package.tgz";then
    entry=$(tar -ztf "$domain_work/package.tgz" | awk '$0=="cn.srs"||$0=="./cn.srs"{print}')
    if [ "$entry" = cn.srs ] || [ "$entry" = ./cn.srs ];then tar -zxOf "$domain_work/package.tgz" "$entry" | head -c 1048577 > "$domain_work/cn.new";fi
   fi
   rm -f "$domain_work/package.tgz"
  else curl --cacert "$domain_work/ca.pem" --noproxy '*' -fsSL --connect-timeout 10 --max-time 40 --max-filesize 1048576 "$domain_url" -o "$domain_work/cn.new" || rm -f "$domain_work/cn.new";fi
  if domain_asset_valid "$domain_hash" "$domain_work/cn.new";then
   mv "$domain_work/cn.new" "$domain_file" || return 1
   domain_found=1;break
  fi
 done
 rm -f "$domain_work/cn.new" "$domain_work/ca.pem"
 [ "$domain_found" = 1 ] || return 1
 domain_asset_sync
}
