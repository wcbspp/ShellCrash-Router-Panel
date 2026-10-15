#!/bin/sh
# Sourced after the small application snapshot is prepared. Kernel archives
# stay in their existing immutable object; never duplicate them in router RAM.
backup_resources_pack(){
 resources="$D/runtime-assets-backup.tar.gz"
 available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
 limit=$(((available-protect_kb-512)*1024));[ "$limit" -le 2000000 ] || limit=2000000
 [ "$limit" -ge 32768 ] || { echo '运行资源备份暂缓：可用内存不足';return 1; }
 printf 'format=2\nmodel=%s\ncreated=%s\n' "$(dav_model)" "$(date +%s)" > "$D/runtime-backup.info"
 set -- "${D#/tmp/}/runtime-backup.info"
 [ ! -d /tmp/ShellCrash-dashboard ] || set -- "$@" ShellCrash-dashboard
 [ "$(dav_model)" != K2P ] || [ ! -d /tmp/ShellCrash/ruleset ] || set -- "$@" ShellCrash/ruleset
 : > "$D/runtime-tar.error"
 tar -cf - -C /tmp "$@" 2> "$D/runtime-tar.error" | gzip -c | head -c "$((limit+1))" > "$resources.new"
 [ "$(wc -c < "$resources.new")" -le "$limit" ] && [ ! -s "$D/runtime-tar.error" ] && gzip -t "$resources.new" || {
  rm -f "$resources.new";echo '运行资源打包失败，远端最新完整备份未替换';return 1;
 }
 mv "$resources.new" "$resources"
}
backup_set_publish(){
 remote_transfer_ready && [ "$(remote_transport)" = webdav ] || return 2
 app=$1;app_hash=$(remote_hash < "$app");app_size=$(wc -c < "$app" | tr -d ' ')
 printf '%s' "$hash" | grep -Eq '^[a-f0-9]{64}$' || return 1
 remote_has core "$hash" tar.gz || { echo '当前内核的精确备份缺失，未发布完整备份';return 1; }
 if [ "$(dav_model)" = AX5 ];then
  core_size=$(wc -c < "$C/cache/core-armv7.tar.gz" | tr -d ' ')
  core_kind=$KIND;tool_version=$(cat /data/ShellCrash-tool/version)
 else
  core_size=$(sed -n 's/^archive_size=//p' "$C/configs/core-installed.info")
  core_kind=singbox;tool_version=$(cat "$C/version")
 fi
 case "$core_size" in ''|*[!0-9]*)return 1;;esac
 for v in "$version" "$panel_version" "$tool_version";do printf '%s' "$v" | grep -Eq '^[A-Za-z0-9._+-]{1,40}$' || return 1;done
 previous="$D/full-backup-previous.json";index="$D/full-backup-index.json"
 # Capture the previous pointer before any uploads. A failed component upload
 # must leave the old pointer AND every object it references available.
 dav_latest application > "$previous" || :
 [ ! -s "$previous" ] || dav_publish_index "$(dav_base)/backups/application-previous.json" "$previous" || return 1
 backup_resources_pack || return 1
 resource_hash=$(remote_hash < "$resources");resource_size=$(wc -c < "$resources" | tr -d ' ')
 app_url=$(dav_object backup "$app_hash" tar.gz);resource_url=$(dav_object runtime "$resource_hash" tar.gz)
 dav_store_file "$app" "$app_url" || return 1
 dav_store_file "$resources" "$resource_url" || return 1
 # This identity describes the exact set, rather than only its application tar.
 set_hash=$(printf '%s\n%s\n%s\n' "$app_hash" "$hash" "$resource_hash" | remote_hash)
 printf '{"format":2,"scope":"full-application","model":"%s","created":%s,"size":%s,"sha256":"%s","core_kind":"%s","core_version":"%s","core_sha256":"%s","tool_version":"%s","panel_version":"%s","files":[{"name":"application.tar.gz","path":"backups/backup-%s.tar.gz","size":%s,"sha256":"%s"},{"name":"core.tar.gz","path":"objects/core-%s.tar.gz","size":%s,"sha256":"%s"},{"name":"runtime-assets.tar.gz","path":"objects/runtime-%s.tar.gz","size":%s,"sha256":"%s"}],"source":"installed-files","credentials":"excluded","default_restore":"programs-preserve-settings"}\n' \
  "$(dav_model)" "$(date +%s)" "$((app_size+core_size+resource_size))" "$set_hash" "$core_kind" "$version" "$hash" "$tool_version" "$panel_version" \
  "$app_hash" "$app_size" "$app_hash" "$hash" "$core_size" "$hash" "$resource_hash" "$resource_size" "$resource_hash" > "$index"
 [ "$(wc -c < "$index")" -le 2048 ] || return 1
 dav_publish_index "$(dav_base)/backups/application-latest.json" "$index" || return 1
 cp "$index" "$D/remote-application.json";printf '%s\n' "$set_hash" > "$D/backup-sha"
 # Only obsolete rolling application/runtime objects can be removed. Core,
 # database caches and the separate immutable baseline namespace are retained.
 for kind in backup runtime;do
  old=$(sed -n "s/.*\"path\":\"[a-z]*\/$kind-\([a-f0-9]*\)\.tar.gz\".*/\1/p" "$previous")
  [ "$kind" != backup ] || [ -n "$old" ] || old=$(sed -n 's/.*"format":1.*"sha256":"\([a-f0-9]*\)".*/\1/p' "$previous")
  now=$app_hash;[ "$kind" != runtime ] || now=$resource_hash
  if [ "$old" != "$now" ] && printf '%s' "$old" | grep -Eq '^[a-f0-9]{64}$';then
   dav_curl --fail -X DELETE --max-time 6 "$(dav_object "$kind" "$old" tar.gz)" -o /dev/null || echo '新完整备份已保存；旧对象清理待重试' >&2
  fi
 done
 dav_curl --fail -X DELETE --max-time 6 "$(dav_base)/backups/application-previous.json" -o /dev/null || echo '新完整备份已保存；临时旧清单清理待重试' >&2
 rm -f "$resources" "$previous" "$D/runtime-backup.info" "$D/runtime-tar.error"
}
