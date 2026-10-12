#!/bin/sh
# Plain text settings, never evaluated as shell code.
. "$C/starts/remote.sh"
mirror_get(){ sed -n "s/^$1=//p" "$C/configs/mirror.conf" 2>/dev/null | head -1; }
mirror_base(){ [ "$(remote_transport)" != webdav ] && remote_ready && mirror_get base; }
mirror_core_url(){
 base=$(mirror_base); [ -n "$base" ] || return 1
 sha=$(release_get sha256 "$1"); blob=$(release_get git_blob "$1")
 if [ -n "$sha" ]; then printf '%s/core-%s.tar.gz\n' "$base" "$sha"; else printf '%s/blob-%s.tar.gz\n' "$base" "$blob"; fi
}
mirror_put(){
 remote_ready || return 2
 suffix=txt;[ "$1" != core ] || suffix=tar.gz;[ "$1" != cn ] || suffix=srs;[ "$1" != backup ] || suffix=tar.gz
 digest=$(remote_put "$1" "$2" "$suffix") || return 1
 printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$digest" > "$C/configs/mirror.last"
 event "Remote synchronized and read-back verified: $1 $digest"
}
mirror_required_put(){
 remote_ready || return 0
 if ! mirror_put "$1" "$2";then date +%s > "$C/configs/mirror.pending";event 'Remote synchronization pending; local update continues';fi
 return 0
}

mirror_probe(){
 base=$(mirror_base)
 remote_ready || { printf '{"available":false,"configured":false}\n' > "$D/mirror-check.json"; return 0; }
 if remote_manifest core > "$D/mirror-check.info" && release_valid "$D/mirror-check.info";then :
elif [ -n "$base" ] && curl -4 --noproxy '*' -fsSL --connect-timeout 5 --max-time 12 --max-filesize 2048 "$base/core-info.txt" -o "$D/mirror-check.info" && release_valid "$D/mirror-check.info"; then :
else rm -f "$D/mirror-check.info";fi
if [ -s "$D/mirror-check.info" ];then
  printf '{"available":true,"configured":true,"version":"%s","sha256":"%s","checked":%s}\n' "$(release_get version "$D/mirror-check.info")" "$(release_get sha256 "$D/mirror-check.info")" "$(date +%s)" > "$D/mirror-check.json"
 else printf '{"available":false,"configured":true,"checked":%s}\n' "$(date +%s)" > "$D/mirror-check.json"; fi
 rm -f "$D/mirror-check.info"
}
