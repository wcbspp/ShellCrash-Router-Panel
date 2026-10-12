#!/bin/sh
# Bind an already prepared Entware directory; do not initialize or replace identities.
set -e
path=${1:-$(/sbin/uci -c /etc/mixbox/mbdb -q get entware.main.path)}
[ -n "$path" ] || path=/etc/mixbox/.Entware
case "$path" in /*) ;; *) echo 'Entware 路径必须是绝对路径' >&2;exit 1;; esac
[ -x "$path/bin/opkg" ] && [ -f "$path/etc/init.d/rc.unslung" ] || { echo 'Entware 尚未完整安装' >&2;exit 1; }
mkdir -p /opt
bound(){ [ "$(stat -c '%d:%i' "$path")" = "$(stat -c '%d:%i' /opt)" ]; }
bound && exit 0
[ -z "$(pidof zerotier-one)" ] || { echo '请先停止 ZeroTier 再迁移 Entware 挂载' >&2;exit 1; }
old=/opt/var/lib/zerotier-one/identity.secret
new=$path/var/lib/zerotier-one/identity.secret
if [ -s "$old" ];then
 [ -s "$new" ] && cmp -s "$old" "$new" || { echo 'ZeroTier 身份尚未迁移，未改变挂载' >&2;exit 1; }
fi
mount -o bind "$path" /opt
bound || { umount /opt;echo 'Entware 挂载验证失败' >&2;exit 1; }
