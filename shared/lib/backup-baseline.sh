#!/bin/sh
# A baseline is a separate immutable copy, never a reference to rolling objects.
# Source after remote.sh. COPY executes on the DAV server, without a second
# kernel archive or a complete ZIP in router RAM. Unsupported COPY fails closed.
baseline_check_slot(){
 remote_transfer_ready && [ "$(remote_transport)" = webdav ] || return 2
 case "$1" in create|replace) :;;*)return 2;;esac
 code=$(dav_curl --max-time 4 --max-filesize 2048 -o /dev/null -w '%{http_code}' "$(dav_base)/baselines/baseline-latest.json") || return 1
 case "$code:$1" in 404:create|404:replace|200:replace)return 0;;200:create)echo '基础版本已存在，请使用替换操作并确认';return 3;;*)echo '无法确认现有基础版本，未开始创建';return 1;;esac
}
baseline_copy(){
 source_url=$1;target_url=$2;expected=$3
 copy_code=$(dav_curl -X COPY -H "Destination: $target_url" -H 'Overwrite: F' -o /dev/null -w '%{http_code}' "$source_url") || return 1
 case "$copy_code" in 201|204) :;;*)echo "服务器不能复制基础备份（HTTP=$copy_code），原基础版本保留" >&2;return 1;;esac
 [ "$(dav_read_hash "$target_url")" = "$expected" ] || { echo '基础备份组件回读校验失败，原基础版本保留' >&2;return 1; }
}
baseline_create(){
 remote_transfer_ready && [ "$(remote_transport)" = webdav ] || return 2
 # The caller produces a fresh, checked full backup, not a stale catalog entry.
 index="$D/full-backup-index.json"
 [ -s "$index" ] && [ "$(wc -c < "$index")" -le 2048 ] || return 1
 grep -q '"format":2,"scope":"full-application"' "$index" || return 1
 model=$(dav_model);grep -q '"model":"'"$model"'"' "$index" || return 1
 parser="$C/starts/backup-manifest.awk";[ "$model" != AX5 ] || parser="$C/ax5/backup-manifest.awk"
 LC_ALL=C awk -v expected_model="$model" -f "$parser" "$index" > "$D/baseline-records.tsv" || return 1
 set_hash=$(sed -n 's/.*"size":[0-9]*,"sha256":"\([a-f0-9]*\)","core_kind".*/\1/p' "$index")
 printf '%s' "$set_hash" | grep -Eq '^[a-f0-9]{64}$' || return 1
 old_pointer="$D/baseline-previous.json"
 old_code=$(dav_curl --max-time 4 --max-filesize 2048 -o "$old_pointer" -w '%{http_code}' "$(dav_base)/baselines/baseline-latest.json") || return 1
 case "$old_code" in
  200)[ "$(wc -c < "$old_pointer")" -le 2048 ] && dav_publish_index "$(dav_base)/baselines/baseline-previous.json" "$old_pointer" || return 1;;
  404)rm -f "$old_pointer";;
  *)echo '读取原基础版本失败，未开始替换' >&2;return 1;;
 esac
 nonce=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
 stamp=$(date +%s);point="recovery-$stamp-$nonce"
 dir="$(dav_base)/baselines/$point"
 dav_mkdir "$(dav_base)/baselines" && dav_mkdir "$dir" || return 1
 for name in application core runtime-assets;do
  line=$(awk -F '\t' -v name="$name.tar.gz" '$1==name{print $2,$3,$4}' "$D/baseline-records.tsv")
  set -- $line
  [ "$#" = 3 ] || return 1
  case "$name:$1" in application:backups/backup-*.tar.gz|core:objects/core-*.tar.gz|runtime-assets:objects/runtime-*.tar.gz) :;;*)return 1;;esac
  printf '%s' "$3" | grep -Eq '^[a-f0-9]{64}$' || return 1
  case "$2" in ''|*[!0-9]*)return 1;;esac
  [ "$2" -gt 0 ] && [ "$2" -le 40000000 ] || return 1
  case "$name" in application)kind=backup;;core)kind=core;;runtime-assets)kind=runtime;;esac
  [ "${1##*/}" = "$kind-$3.tar.gz" ] || return 1
  baseline_copy "$(dav_base)/$1" "$dir/$name.tar.gz" "$3" || return 1
 done
 # Only the three component paths are changed. Identity and versions stay exact.
 sed -e 's/"scope":"full-application"/"scope":"full-application-baseline"/' \
     -e 's|"path":"backups/backup-[a-f0-9]*.tar.gz"|"path":"application.tar.gz"|' \
     -e 's|"path":"objects/core-[a-f0-9]*.tar.gz"|"path":"core.tar.gz"|' \
     -e 's|"path":"objects/runtime-[a-f0-9]*.tar.gz"|"path":"runtime-assets.tar.gz"|' \
     -e 's/"default_restore":"programs-preserve-settings"/"default_restore":"full-confirmed"/' "$index" > "$D/baseline-manifest.json"
 dav_store_file "$D/baseline-manifest.json" "$dir/manifest.json" || return 1
 helper="$C/starts/backup-guide.sh";[ "$model" != AX5 ] || helper="$C/ax5/backup-guide.sh"
 guide="$D/baseline-guide";mkdir -p "$guide"
 sh "$helper" "$guide" "$model" full || return 1
 # ASCII filenames also work with DAV clients without Unicode URL support.
 dav_store_file "$guide/使用说明.txt" "$dir/GUIDE.txt" || return 1
 dav_store_file "$guide/使用说明.txt" "$dir/RESTORE.txt" || return 1
 sed 's|}$|,"path":"baselines/'"$point"'/manifest.json","label":"'"$point"'"}|' "$D/baseline-manifest.json" > "$D/baseline-pointer.json"
 [ "$(wc -c < "$D/baseline-pointer.json")" -le 2048 ] || return 1
 dav_publish_index "$(dav_base)/baselines/baseline-latest.json" "$D/baseline-pointer.json" || return 1
 cp "$D/baseline-pointer.json" "$D/remote-baseline.json"
 dav_curl --fail -X DELETE "$(dav_base)/baselines/baseline-previous.json" -o /dev/null || :
 rm -rf "$guide";rm -f "$D/baseline-manifest.json" "$D/baseline-pointer.json"
 rm -f "$old_pointer" "$D/baseline-records.tsv"
 echo '基础版本已独立保存并校验；日常备份不会覆盖，恢复时需要确认完整覆盖配置'
}
