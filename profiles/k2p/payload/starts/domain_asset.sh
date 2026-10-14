#!/bin/sh
# Small fixed DNS rule asset; no persistent copy in K2P Storage.
domain_asset_valid(){ printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null 2>&1; }
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
 domain_hash=$1;domain_file=$2;domain_work=$3
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
 for domain_url in $domain_custom ${PANEL_CN_MIRROR:-} https://raw.githubusercontent.com/DustinWin/ruleset_geodata/877462de3ab7fe81ad4b8bd0f7d4a8fd9df363fe/cn.srs https://testingcf.jsdelivr.net/gh/DustinWin/ruleset_geodata@877462de3ab7fe81ad4b8bd0f7d4a8fd9df363fe/cn.srs;do
  if curl --cacert "$domain_work/ca.pem" --noproxy '*' -fsSL --connect-timeout 10 --max-time 40 --max-filesize 1048576 "$domain_url" -o "$domain_work/cn.new" && domain_asset_valid "$domain_hash" "$domain_work/cn.new";then
   mv "$domain_work/cn.new" "$domain_file" || return 1
   domain_found=1;break
  fi
 done
 rm -f "$domain_work/cn.new" "$domain_work/ca.pem"
 [ "$domain_found" = 1 ] || return 1
 domain_asset_sync
}
