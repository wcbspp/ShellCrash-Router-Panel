#!/bin/sh
# Sourced by the authenticated manager under its operation lock.
. "$C/starts/mirror_lib.sh"
if [ "$act" = mirrorsave ] || [ "$act" = mirrortest ]; then
 [ "$(cat "$D/kind")" = mirror ] || { fail invalid_upload; exit 1; }
 sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' > "$D/upload.b64"
 base64 -d "$D/upload.b64" > "$D/mirror.new" 2>/dev/null || { fail invalid_upload; exit 1; }
 . "$C/starts/remote-settings.sh"
 if [ "$act" = mirrortest ];then
  phase syncing '正在测试候选 WebDAV 设置'
  if remote_settings_test "$D/mirror.new" > "$D/remote-test.log" 2>&1;then phase done 'WebDAV 测试通过，尚未保存';else fail "$(remote_settings_error "$D/remote-test.log")";exit 1;fi
  rm -f "$D/mirror.new" "$D/upload.b64" "$D/upload.parts";exit 0
 fi
 remote_settings_commit "$D/mirror.new" > "$D/remote-save.error" 2>&1 || { rm -f "$D/mirror.new" "$D/upload.b64" "$D/upload.parts";fail "$(tail -1 "$D/remote-save.error")";exit 1; }
 rm -f "$D/mirror.new" "$D/upload.b64" "$D/upload.parts"
 phase done mirror_saved;event 'WebDAV settings saved';exit 0
fi
if [ "$act" = mirrorverify ];then
 phase syncing '正在验证远程仓库'
 remote_verify >> "$D/worker.log" 2>&1 || { fail 'WebDAV 验证失败，请检查地址、账号密码与读写权限';exit 1; }
 save_safe || { rm -f "$C/configs/remote.verified";fail persistent_save_failed;exit 1; }
 phase done '远程仓库验证通过';exit 0
fi
remote_ready || { fail '请先开启并验证远程仓库';exit 1; }
phase syncing mirror_syncing
"$C/starts/backup-app.sh" remote >> "$D/worker.log" 2>&1 || { fail mirror_sync_failed;exit 1; }
. "$C/starts/core_release.sh"
mirror_probe
save_safe || { fail persistent_save_failed;exit 1; }
rm -f "$C/configs/mirror.pending"
phase done mirror_synced
