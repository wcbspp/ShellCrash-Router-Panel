#!/bin/sh
# Five base64-valued lines keep credentials out of shell syntax and API state.
remote_settings_save()(
 umask 077
 input=$1;stage="$D/remote-settings.$$"
 mkdir "$stage" || return 1
 trap 'rm -rf "$stage"' EXIT
 [ "$(wc -c < "$input")" -le 4096 ] && [ "$(wc -l < "$input")" -eq 5 ] || return 2
 enabled=$(sed -n 's/^enabled=//p' "$input");case "$enabled" in 0|1) :;;*)return 2;;esac
 [ "$(sed -n 's/^transport=//p' "$input")" = webdav ] || return 2
 for field in base user password;do
  encoded=$(sed -n "s/^${field}_b64=//p" "$input")
  printf '%s' "$encoded" | base64 -d > "$stage/$field" 2>/dev/null || return 2
  [ "$(wc -c < "$stage/$field")" -le 1024 ] || return 2
  hexdump -v -e '1/1 "%u "' "$stage/$field" > "$stage/bytes" || return 2
  awk '{for(i=1;i<=NF;i++)if($i<32||$i==127)bad=1}END{exit bad}' "$stage/bytes" || return 2
 done
 base=$(cat "$stage/base");base=${base%/};user=$(cat "$stage/user");password=$(cat "$stage/password")
 if [ -n "$base" ];then
  printf '%s' "$base" | grep -Eq '^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%+-]+)*$' || return 2
  printf '%s' "$base" | grep -Eq '(^|/)(\.\.|\.)(/|$)|%2[eEfF]|%2[fF]|%5[cC]' && return 2
 fi
 case "$user" in *:*)return 2;;esac
 [ "$enabled" != 1 ] || { [ -n "$base" ] && [ -n "$user" ]; } || return 2
 if [ -z "$password" ];then
  [ "$base" = "$(sed -n 's/^base=//p' "$C/configs/mirror.conf" 2>/dev/null)" ] && [ "$user" = "$(cat "$C/configs/webdav.user" 2>/dev/null)" ] && [ -s "$C/configs/webdav.auth" ] && cp "$C/configs/webdav.auth" "$stage/auth"
  [ "$enabled" != 1 ] || [ -s "$stage/auth" ] || return 2
 else
  escaped=$(printf '%s:%s' "$user" "$password" | sed 's/\\/\\\\/g;s/"/\\"/g')
  printf 'user = "%s"\n' "$escaped" > "$stage/auth"
 fi
 printf 'enabled=%s\ntransport=webdav\nbase=%s\ntarget=\n' "$enabled" "$base" > "$stage/conf"
 if [ "$enabled" = 1 ] && [ "${SC_REMOTE_REQUIRE_TEST:-0}" = 1 ];then
  candidate=$(cat "$stage/conf" "$stage/auth" "$stage/user" | remote_hash)
  tested=$(cat "$D/remote-draft.verified" 2>/dev/null)
  checked=$(cat "$D/remote-draft.checked" 2>/dev/null)
  case "$checked" in ''|*[!0-9]*)return 3;;esac
  age=$(( $(date +%s)-checked ))
  [ "$candidate" = "$tested" ] && [ "$age" -ge 0 ] && [ "$age" -le 900 ] || return 3
 fi
 for name in mirror.conf webdav.auth webdav.user remote.verified remote.checked;do
  [ ! -f "$C/configs/$name" ] || cp "$C/configs/$name" "$stage/$name.previous"
 done
 mv "$stage/conf" "$C/configs/mirror.conf"
 if [ -f "$stage/auth" ];then mv "$stage/auth" "$C/configs/webdav.auth";else rm -f "$C/configs/webdav.auth";fi
 printf '%s' "$user" > "$C/configs/webdav.user"
 chmod 600 "$C/configs/mirror.conf" "$C/configs/webdav.user"
 [ ! -f "$C/configs/webdav.auth" ] || chmod 600 "$C/configs/webdav.auth"
 rm -f "$C/configs/remote.verified"
 rm -f "$C/configs/remote.checked" "$D/remote-application.json" "$D/remote-config.json"
 if [ "$enabled" = 1 ] && [ "${SC_REMOTE_REQUIRE_TEST:-0}" = 1 ];then
  cp "$D/remote-draft.verified" "$C/configs/remote.verified"
  cp "$D/remote-draft.checked" "$C/configs/remote.checked"
 fi
 if type save_safe >/dev/null 2>&1 && ! save_safe;then
  for name in mirror.conf webdav.auth webdav.user remote.verified remote.checked;do
   if [ -f "$stage/$name.previous" ];then cp "$stage/$name.previous" "$C/configs/$name";else rm -f "$C/configs/$name";fi
  done
  return 1
 fi
 [ "${SC_REMOTE_REQUIRE_TEST:-0}" != 1 ] || rm -f "$D/remote-draft.verified" "$D/remote-draft.checked"
 echo '备份设置已保存'
)

# Return a useful save error without exposing draft credentials.
remote_settings_commit(){
 if SC_REMOTE_REQUIRE_TEST=1 remote_settings_save "$1";then return 0;else result=$?;fi
 case "$result" in
  3)echo '测试结果已过期、被其他操作替换或参数已变化，请重新测试连接后保存；原设置未改动';;
  2)echo 'WebDAV 设置无效，请检查地址、账号和密码；原设置未改动';;
  *)echo 'WebDAV 设置保存失败，已恢复原设置，请检查本机存储空间';;
 esac
 return "$result"
}

# Test candidate credentials in RAM; installed configuration remains untouched.
remote_settings_error(){
 log=$1
 code=$(sed -n 's/.*HTTP=\([0-9][0-9][0-9]\).*/\1/p;s/.*returned error: \([0-9][0-9][0-9]\).*/\1/p' "$log"|tail -1)
 case "$code" in
  401)echo 'WebDAV 账号或密码不正确（HTTP 401），原设置未改动';return;;
  403)echo 'WebDAV 账号没有所需读写权限（HTTP 403），原设置未改动';return;;
  404)echo 'WebDAV 路径不存在（HTTP 404），请检查地址';return;;
  405)echo '此地址不支持所需 WebDAV 写入操作（HTTP 405）';return;;
 esac
 if grep -q 'curl: (28)' "$log";then echo 'WebDAV 连接或读写超时，原设置未改动'
 elif grep -q 'curl: (7)' "$log";then echo '无法连接 WebDAV 服务器，请检查地址和端口'
 else echo 'WebDAV 测试失败，请检查地址、账号密码和读写权限；原设置未改动';fi
}
remote_settings_test()(
 umask 077
 input=$1;original=$C;probe="$D/remote-probe.$$"
 case "$C" in /data/ShellCrash) REMOTE_MODEL=AX5;;*)REMOTE_MODEL=K2P;;esac
 mkdir -p "$probe/configs" || return 1
 trap 'rm -rf "$probe"' EXIT
 rm -f "$D/remote-draft.verified" "$D/remote-draft.checked"
 for name in mirror.conf webdav.auth webdav.user;do
  [ ! -f "$C/configs/$name" ] || cp "$C/configs/$name" "$probe/configs/$name"
 done
 sed 's/^enabled=[01]$/enabled=1/' "$input" > "$probe/input"
 C=$probe
 save_safe(){ :; }
 SC_REMOTE_REQUIRE_TEST=0 remote_settings_save "$probe/input" || return 2
 remote_verify || return 1
 cp "$C/configs/remote.verified" "$D/remote-draft.verified"
 cp "$C/configs/remote.checked" "$D/remote-draft.checked"
 echo 'WebDAV 候选设置测试通过，可保存'
)
