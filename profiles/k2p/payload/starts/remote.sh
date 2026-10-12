#!/bin/sh
# Shared AX5 / K2P transport; sourced. Settings are data, never shell code.
remote_get_setting(){ sed -n "s/^$1=//p" "$C/configs/mirror.conf" 2>/dev/null | head -1; }
remote_enabled(){ [ "$(remote_get_setting enabled)" = 1 ]; }
remote_hash(){ if type sha256sum >/dev/null 2>&1;then sha256sum | awk '{print $1}';else openssl dgst -sha256 | awk '{print $NF}';fi; }
remote_key(){ if [ "$C" = /data/ShellCrash ];then printf '%s/configs/mirror-id\n' "$C";else printf '%s/configs/mirror_key\n' "$C";fi; }
remote_transport(){ t=$(remote_get_setting transport);printf '%s\n' "${t:-ssh}"; }
remote_fingerprint(){ if [ "$(remote_transport)" = webdav ];then cat "$C/configs/mirror.conf" "$C/configs/webdav.auth" "$C/configs/webdav.user" 2>/dev/null | remote_hash;return;fi; { cat "$C/configs/mirror.conf" "$C/configs/mirror_known_hosts"; cat "$(remote_key)"; } 2>/dev/null | remote_hash; }
remote_ready(){ remote_enabled || return 2;if [ "$(remote_transport)" = webdav ];then [ -s "$C/configs/webdav.auth" ] && [ -n "$(remote_get_setting base)" ] && [ "$(remote_fingerprint)" = "$(cat "$C/configs/remote.verified" 2>/dev/null)" ];return;fi; [ -s "$(remote_key)" ] && [ -s "$C/configs/mirror_known_hosts" ] && [ "$(remote_fingerprint)" = "$(cat "$C/configs/remote.verified" 2>/dev/null)" ]; }
remote_ssh()(
 target=$(remote_get_setting target)
 printf '%s' "$target" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}@[A-Za-z0-9.-]+:[0-9]{1,5}$' || return 2
 peer=${target%:*};port=${target##*:};[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 2
 key=$(remote_key);[ -s "$key" ] && [ -s "$C/configs/mirror_known_hosts" ] || return 2
 # Dropbear has no UserKnownHostsFile/BatchMode support on these firmwares.
 host=${peer#*@};[ "$port" = 22 ] && entry=$host || entry="[$host]:$port"
 awk -v h="$entry" -v bare="$host" '($1==h || $1==bare) && $2 ~ /^ssh-/ && NF==3 {found=1} END {exit !found}' "$C/configs/mirror_known_hosts" || return 2
 mkdir -p "$HOME/.ssh";chmod 700 "$HOME/.ssh"
 touch "$HOME/.ssh/known_hosts";chmod 600 "$HOME/.ssh/known_hosts"
 while IFS= read -r line;do
  grep -Fxq "$line" "$HOME/.ssh/known_hosts" || printf '%s\n' "$line" >> "$HOME/.ssh/known_hosts"
 done < "$C/configs/mirror_known_hosts"
 # Bound the entire request as well as idle time, including a failed authentication.
 exec 3<&0
 ssh -T -K 10 -I 20 -i "$key" -p "$port" "$peer" "$@" <&3 3<&- &
 child=$!
 exec 3<&-
 (sleep 90 & timer=$!;trap 'kill "$timer" 2>/dev/null;exit' TERM INT;wait "$timer";kill "$child" 2>/dev/null) </dev/null >/dev/null 2>&1 &
 watchdog=$!
 if wait "$child";then status=0;else status=$?;fi
 kill "$watchdog" 2>/dev/null || :
 wait "$watchdog" 2>/dev/null || :
 return "$status"
)
remote_ssh_verify()(
 rm -f "$C/configs/remote.verified"
 remote_enabled || { echo '远程仓库已关闭';return 2; }
 [ "$(remote_ssh probe </dev/null)" = 'SCMIRROR/2' ] || { echo 'SSH 身份、指纹或接收器读写验证失败';return 1; }
 # A nonce round trip tests upload and retrieval without sending configuration.
 f="$D/remote-probe.$$";head -c 24 /dev/urandom > "$f"
 h=$(remote_hash < "$f")
 if ! remote_ssh "put probe $h txt" < "$f" > "$f.reply" || [ "$(cat "$f.reply")" != "$h" ] || [ "$(remote_ssh "get probe $h txt" | remote_hash)" != "$h" ];then
  rm -f "$f" "$f.reply";echo '远程仓库上传/拉取校验失败';return 1
 fi
 rm -f "$f" "$f.reply"
 remote_fingerprint > "$C/configs/remote.verified"
 date +%s > "$C/configs/remote.checked"
 echo 'SSH 上传与拉取验证通过'
)
remote_ssh_put()(
 remote_ready || return 2
 kind=$1;file=$2;ext=$3;h=$(remote_hash < "$file")
 reply=$(remote_ssh "put $kind $h $ext" < "$file") || return 1
 [ "$reply" = "$h" ] && [ "$(remote_ssh "get $kind $h $ext" | remote_hash)" = "$h" ] || return 1
 printf '%s\n' "$h"
)
remote_ssh_fetch()(
 remote_ready || return 2
 kind=$1;h=$2;ext=$3;dest=$4;limit=$5
 printf '%s' "$h" | grep -Eq '^[a-f0-9]{64}$' || return 2
 # The receiver enforces its own object size; head bounds the router's tmpfs.
 remote_ssh "get $kind $h $ext" | head -c "$((limit+1))" > "$dest"
 [ "$(wc -c < "$dest")" -le "$limit" ] && [ "$(remote_hash < "$dest")" = "$h" ] && return 0
 rm -f "$dest";return 1
)
remote_ssh_manifest(){ remote_ready || return 2; remote_ssh "manifest $1" | head -c 2049; }
remote_ssh_has(){ remote_ready && [ "$(remote_ssh "stat $1 $2 $3")" = "$2" ]; }

. "$C/starts/webdav.sh"
remote_verify(){ if [ "$(remote_transport)" = webdav ];then dav_verify "$@";else remote_ssh_verify "$@";fi; }
remote_put(){ if [ "$(remote_transport)" = webdav ];then dav_put "$@";else remote_ssh_put "$@";fi; }
remote_fetch(){ if [ "$(remote_transport)" = webdav ];then dav_fetch "$@";else remote_ssh_fetch "$@";fi; }
remote_manifest(){ if [ "$(remote_transport)" = webdav ];then dav_manifest "$@";else remote_ssh_manifest "$@";fi; }
remote_has(){ if [ "$(remote_transport)" = webdav ];then dav_has "$@";else remote_ssh_has "$@";fi; }
