#!/bin/sh
# Standard HTTP/WebDAV methods; no server-side receiver required.
dav_model(){ case "${REMOTE_MODEL:-}" in AX5|K2P)echo "$REMOTE_MODEL";return;;esac;if [ "$C" = /data/ShellCrash ];then echo AX5;else echo K2P;fi; }
dav_base(){ b=$(remote_get_setting base);case "$b" in http://*|https://*)printf '%s/shellcrash-panel/%s\n' "${b%/}" "$(dav_model)";;*)return 2;;esac; }
dav_curl(){ curl -q -4 --config "$C/configs/webdav.auth" --noproxy '*' --globoff --connect-timeout 4 --max-time 60 --silent --show-error "$@"; }
dav_mkdir(){ code=$(dav_curl -X MKCOL -o /dev/null -w '%{http_code}' "$1/") || return 1;case "$code" in 201|405) return 0;;*)echo "WebDAV 创建目录失败 HTTP=$code" >&2;return 1;;esac; }
dav_object(){
 case "$1:$3" in core:tar.gz|dashboard:tar.gz|backup:tar.gz|info:txt|cn:mrs|cn:srs|rules:txt|rules:srs|rules:json|probe:txt) :;;*)return 2;;esac
 printf '%s' "$2" | grep -Eq '^[a-f0-9]{64}$' || return 2
 dir=objects;[ "$1" != backup ] || dir=backups
 printf '%s/%s/%s-%s.%s\n' "$(dav_base)" "$dir" "$1" "$2" "$3"
}
dav_read_hash(){ dav_curl --fail "$1" | remote_hash; }
dav_latest(){ remote_ready || return 2;case "$1" in application|config) :;;*)return 2;;esac;dav_curl --fail --max-filesize 2048 "$(dav_base)/backups/$1-latest.json" 2>/dev/null | head -c 2049; }
dav_publish_index()(
 pointer=$1;file=$2;hash=$(remote_hash < "$file")
 dav_curl --fail -T "$file" "$pointer.new" -o /dev/null || return 1
 code=$(dav_curl -X MOVE -H "Destination: $pointer" -H 'Overwrite: T' -o /dev/null -w '%{http_code}' "$pointer.new") || return 1
 case "$code" in 201|204) :;;405|501) dav_curl --fail -T "$file" "$pointer" -o /dev/null || return 1;dav_curl --fail -X DELETE "$pointer.new" -o /dev/null || :;;*)echo "WebDAV 索引保存失败 HTTP=$code" >&2;return 1;;esac
 [ "$(dav_read_hash "$pointer")" = "$hash" ]
)
dav_publish_backup()(
 file=$1;hash=$2;scope=application
 [ "${file##*/}" != config-backup.tar.gz ] || scope=config
 previous="$D/dav-$scope-previous.$$";index="$D/dav-$scope-index.$$"
 trap 'rm -f "$previous" "$index"' EXIT
 dav_latest "$scope" > "$previous" || :
 if [ "$C" = /data/ShellCrash ];then
  kind=$(sed -n 's/^KIND=//p' "$C/cache/core.env");version=$(sed -n 's/^VERSION=//p' "$C/cache/core.env");core=$(sed -n 's/^HASH=//p' "$C/cache/core.env");tool=$(cat /data/ShellCrash-tool/version)
 else
  kind=singbox;version=$(sed -n 's/^version=//p' "$C/configs/core-installed.info");core=$(sed -n 's/^sha256=//p' "$C/configs/core-installed.info");tool=$(cat "$C/version")
 fi
 case "$kind" in meta|singbox) :;;*)kind=unknown;;esac
 printf '%s' "$version" | grep -Eq '^v?[0-9.]{1,24}$' || version=unknown
 printf '%s' "$tool" | grep -Eq '^[A-Za-z0-9._-]{1,40}$' || tool=unknown
 printf '%s' "$core" | grep -Eq '^[a-f0-9]{64}$' || core=''
 printf '{"format":1,"model":"%s","scope":"%s","created":%s,"size":%s,"sha256":"%s","core_kind":"%s","core_version":"%s","core_sha256":"%s","tool_version":"%s"}\n' "$(dav_model)" "$scope" "$(date +%s)" "$(wc -c < "$file" | tr -d ' ')" "$hash" "$kind" "$version" "$core" "$tool" > "$index"
 dav_publish_index "$(dav_base)/backups/$scope-latest.json" "$index" || return 1
 cp "$index" "$D/remote-$scope.json"
 old=$(sed -n 's/.*"sha256":"\([a-f0-9]*\)".*/\1/p' "$previous")
 if [ "$old" != "$hash" ] && printf '%s' "$old" | grep -Eq '^[a-f0-9]{64}$';then
  dav_curl --fail -X DELETE "$(dav_object backup "$old" tar.gz)" -o /dev/null || echo '新备份已保存；旧备份清理待重试' >&2
 fi
)
dav_refresh_catalog(){
 for scope in application config;do
  if dav_latest "$scope" > "$D/remote-$scope.new" && [ "$(wc -c < "$D/remote-$scope.new")" -le 2048 ] && grep -q '"format":1' "$D/remote-$scope.new";then mv "$D/remote-$scope.new" "$D/remote-$scope.json";else rm -f "$D/remote-$scope.new" "$D/remote-$scope.json";fi
 done
}
dav_fetch()(
 remote_ready || return 2
 url=$(dav_object "$1" "$2" "$3") || return 2
 dav_curl --fail --max-filesize "$5" "$url" | head -c "$(($5+1))" > "$4"
 [ "$(wc -c < "$4")" -le "$5" ] && [ "$(remote_hash < "$4")" = "$2" ] && return 0
 rm -f "$4";return 1
)
dav_has()(
 remote_ready || return 2
 url=$(dav_object "$1" "$2" "$3") || return 2
 [ "$(dav_read_hash "$url" 2>/dev/null)" = "$2" ]
)
dav_put()(
 remote_ready || return 2
 h=$(remote_hash < "$2");url=$(dav_object "$1" "$h" "$3") || return 2
 if ! dav_curl --fail -T "$2" "$url" -o /dev/null;then echo 'WebDAV 上传失败' >&2;return 1;fi
 [ "$(dav_read_hash "$url")" = "$h" ] || { echo 'WebDAV 回读校验失败' >&2;return 1; }
 if [ "$1" = info ];then
  kind=$(sed -n 's/^KIND=//p' "$2");case "$kind" in meta|singbox) :;;*)kind=core;;esac
  # Publish the small index only after the immutable object has been verified.
  pointer="$(dav_base)/objects/$kind-info.txt"
  dav_publish_index "$pointer" "$2" || return 1
  dav_curl --fail -X DELETE "$url" -o /dev/null || :
 fi
 [ "$1" != backup ] || dav_publish_backup "$2" "$h" || return 1
 printf '%s\n' "$h"
)
dav_manifest()(
 remote_ready || return 2
 case "$1" in meta|singbox|core) :;;*)return 2;;esac
 dav_curl --fail --max-filesize 2048 "$(dav_base)/objects/$1-info.txt" | head -c 2049
)
dav_verify()(
 rm -f "$C/configs/remote.verified"
 remote_enabled || { echo '远程备份已关闭';return 2; }
 [ -s "$C/configs/webdav.auth" ] && [ -n "$(remote_get_setting base)" ] || { echo '请填写 WebDAV 地址、账号和密码';return 2; }
 base=$(remote_get_setting base)
 dav_mkdir "${base%/}/shellcrash-panel" && dav_mkdir "$(dav_base)" && dav_mkdir "$(dav_base)/objects" && dav_mkdir "$(dav_base)/backups" || return 1
 f="$D/dav-probe.$$";head -c 24 /dev/urandom > "$f";h=$(remote_hash < "$f")
 url="$(dav_base)/objects/probe-$h.txt"
 trap 'rm -f "$f"' EXIT
 dav_curl --fail -T "$f" "$url" -o /dev/null || { echo 'WebDAV 写入失败，请检查账号与写权限';return 1; }
 [ "$(dav_read_hash "$url")" = "$h" ] || { echo 'WebDAV 读取或校验失败';return 1; }
 dav_curl --fail -X DELETE "$url" -o /dev/null || { echo 'WebDAV 测试文件清理失败，请检查删除权限';return 1; }
 remote_fingerprint > "$C/configs/remote.verified";date +%s > "$C/configs/remote.checked"
 dav_refresh_catalog
 echo 'WebDAV 写入、读取和清理验证通过'
)

# One small authenticated request on page load; cached for 60 seconds, never used by startup.
dav_status()(
 now=$(date +%s)
 remote_enabled || { printf '{"state":"disabled","checked":%s}\n' "$now";return; }
 remote_ready || { printf '{"state":"unverified","checked":%s}\n' "$now";return; }
 fingerprint=$(remote_fingerprint)
 if [ "$(cat "$D/remote-status.fingerprint" 2>/dev/null)" = "$fingerprint" ];then
  checked=$(sed -n 's/.*"checked":\([0-9]*\).*/\1/p' "$D/remote-status.json" 2>/dev/null)
  if [ -n "$checked" ] && [ "$((now-checked))" -ge 0 ] && [ "$((now-checked))" -lt 60 ];then cat "$D/remote-status.json";return;fi
 fi
 exitcode=0;code=$(dav_curl -X OPTIONS --max-time 4 -o /dev/null -w '%{http_code}' "$(dav_base)/" 2>/dev/null) || exitcode=$?
 state=unreachable
 if [ "$exitcode" = 0 ];then case "$code" in 2??|3??|405) state=connected;;401|403)state=unauthorized;;*)state=error;;esac;fi
 printf '{"state":"%s","checked":%s,"http":%s}\n' "$state" "$now" "${code:-0}" | sed 's/"http":000/"http":0/' > "$D/remote-status.json"
 printf '%s\n' "$fingerprint" > "$D/remote-status.fingerprint"
 cat "$D/remote-status.json"
)
