#!/bin/sh
# Read-only recovery inspection. No extraction, service stop, config write or
# executable restore is allowed here. Work files contain metadata, never keys.
set -eu
umask 077
case "${1:-}" in
 ax5)C=/data/ShellCrash;D=/tmp/ShellCrash;helper="$C/ax5";;
 k2p)C=/etc/storage/ShellCrash;D=/tmp/sc-admin;helper="$C/starts";;
 *)exit 2;;
esac
# Tests use an isolated fixture, without changing production command arguments.
if [ "${SC_RECOVERY_FIXTURE:-}" = 1 ];then C=$SC_RECOVERY_C;D=$SC_RECOVERY_D;helper=$SC_RECOVERY_HELPER;fi
id=${2:-};case "$id" in ''|*[!a-f0-9]*)exit 2;;esac
[ "${#id}" = 8 ] || exit 2
export C D
. "$helper/remote.sh"
result="$D/recovery-plan.json";work="$D/recovery-check-$id"
rm -f "$result";mkdir "$work"
trap 'rm -rf "$work";rm -f "$D/upload-restore" "$D/upload-id-restore"' EXIT
reject(){ printf '%s\n' "$1" >&2;exit 1; }
[ "$(cat "$D/upload-id-restore" 2>/dev/null)" = "$id" ] || reject '恢复检查请求已过期，请重新选择'
[ -s "$D/upload-restore" ] && [ "$(wc -c < "$D/upload-restore")" -le 200 ] || reject '恢复检查请求格式不正确'
source='';path='';fields=''
while IFS= read -r line;do
 case "$line" in
  source=*)[ -z "$source" ] || reject '重复的恢复来源';source=${line#source=};;
  path=*)[ -z "$fields" ] || reject '重复的恢复路径';path=${line#path=};fields=path;;
  *)reject '恢复请求含未知字段';;
 esac
done < "$D/upload-restore"
case "$source" in latest|baseline)[ -z "$path" ] || reject '此来源不接受手动路径';;imports)
 printf '%s' "$path" | LC_ALL=C grep -Eq '^imports/[A-Za-z0-9][A-Za-z0-9_-]{0,63}/manifest.json$' || reject '请使用 imports/备份名/manifest.json，备份名使用字母、数字、短横线或下划线';;
 *)reject '请选择有效的恢复来源';;
esac
[ "$(remote_transport)" = webdav ] && remote_transfer_ready || reject '请先开启 WebDAV，测试连接并保存；当前连接不可用'
base=$(dav_base);model=$(dav_model)
parser="$helper/backup-manifest.awk"
fetch_metadata(){
 (status=0;dav_curl --fail --max-time 10 --max-filesize 16384 "$base/$1" || status=$?;printf '%s\n' "$status" > "$work/meta-status") | head -c 16385 > "$work/manifest.json"
 [ "$(cat "$work/meta-status")" = 0 ] && [ -s "$work/manifest.json" ] && [ "$(wc -c < "$work/manifest.json")" -le 16384 ]
}
legacy=0;pointer_hash=''
case "$source" in
 latest)path=backups/application-latest.json;prefix='';;
 baseline)
  fetch_metadata baselines/baseline-latest.json || reject '读取基础备份记录失败'
  path=$(LC_ALL=C awk -v expected_model="$model" -v mode=pointer -f "$parser" "$work/manifest.json") || reject '基础备份记录损坏或机型不匹配'
  layout=$(LC_ALL=C awk -v expected_model="$model" -v mode=pointerlayout -f "$parser" "$work/manifest.json") || reject '基础备份索引不正确'
  if [ "$layout" = legacy ];then
   legacy=1
   pointer_hash=$(LC_ALL=C awk -v expected_model="$model" -v mode=pointerhash -f "$parser" "$work/manifest.json") || reject '基础备份清单校验值缺失'
  fi
  prefix=${path%/manifest.json}/;;
 imports)prefix=${path%/manifest.json}/;;
esac
fetch_metadata "$path" || reject '备份清单未找到或读取失败，请检查目录和文件名'
[ "$legacy" != 1 ] || [ "$(remote_hash < "$work/manifest.json")" = "$pointer_hash" ] || reject '旧基础备份清单校验失败'
LC_ALL=C awk -v expected_model="$model" -f "$parser" "$work/manifest.json" > "$work/records.tsv" || reject '备份清单损坏、缺少组件或机型不匹配'
LC_ALL=C awk -v expected_model="$model" -v mode=plan -v legacy="$legacy" -f "$parser" "$work/manifest.json" > "$work/plan.json" || reject '备份版本信息不完整，不能作为恢复来源'
# Verify set identity (application/core/runtime hashes in canonical order).
expected=$(sed -n 's/.*"sha256":"\([a-f0-9]*\)","size".*/\1/p' "$work/plan.json")
actual=$(awk -F '\t' 'NF==4{print $4}' "$work/records.tsv" | remote_hash)
[ "$legacy" = 1 ] || [ "$expected" = "$actual" ] || reject '备份组合校验失败，组件可能来自不同备份'
verify_stream(){
 url=$1;size=$2;expected_hash=$3
 # Stock K2P has no mkfifo. Inherit a pipe as fd3 for the body, while curl's
 # write-out reports its actual body byte count to a tiny metadata file. A
 # bounded head also protects against a response without Content-Length.
 (status=0;dav_curl --fail --max-time 90 --max-filesize "$size" -o /proc/self/fd/3 -w '%{size_download}' "$url" > "$work/count" || status=$?;printf '%s\n' "$status" > "$work/curl-status") 3>&1 |
  head -c "$((size+1))" | remote_hash > "$work/hash"
 [ "$(cat "$work/curl-status")" = 0 ] && [ "$(cat "$work/count" | tr -d ' ')" = "$size" ] && [ "$(cat "$work/hash")" = "$expected_hash" ]
}
tab=$(printf '\t')
while IFS="$tab" read -r name component size hash;do
 case "$name" in application.tar.gz|core.tar.gz|runtime-assets.tar.gz) :;;*)continue;;esac
 # Prefix is fixed per source. The parser has rejected absolute/traversal URLs.
 case "$source:$component" in
  latest:backups/backup-*.tar.gz|latest:objects/core-*.tar.gz|latest:objects/runtime-*.tar.gz) :;;
  latest:*)reject '日常备份组件位置不正确';;
 esac
 if [ "${SC_RECOVERY_FIXTURE:-}" != 1 ];then
  protect=$(sed -n 's/^protect_mb=//p' "$C/configs/memory.conf" 2>/dev/null | head -1)
  if [ "$model" = AX5 ];then protect=$(lua -e "print(dofile('$C/ax5/common.lua').limits().protect_mb)");fi
  protect=${protect:-12};case "$protect" in *[!0-9]*)reject '内存保护设置无效';;esac
  [ "$protect" -ge 12 ] && [ "$protect" -le 64 ] || reject '内存保护设置无效'
  available=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
  [ "${available:-0}" -ge "$((protect*1024+1024))" ] || reject '可用内存不足，校验已暂停；未停止代理'
 fi
 remote_transfer_ready || reject '校验中 WebDAV 连接断开，检查未完成'
 verify_stream "$base/$prefix$component" "$size" "$hash" || reject '备份组件缺失、损坏、大小不符或连接中断；当前设备未改动'
done < "$work/records.tsv"
# This inspection is transport verification, NOT archive/ELF/config validation.
# Never claim executable readiness before the independent restore transaction exists.
printf '{"id":"%s","source":"%s","checked":%s,"verified":true,"executor_ready":false,"archive_checked":false,"manifest_sha256":"%s","backup":' "$id" "$source" "$(date +%s)" "$(remote_hash < "$work/manifest.json")" > "$result.new"
cat "$work/plan.json" >> "$result.new";printf '}\n' >> "$result.new"
mv "$result.new" "$result"
echo '组件大小与 SHA256 校验通过；未解包、未执行恢复，当前配置保持不变'
