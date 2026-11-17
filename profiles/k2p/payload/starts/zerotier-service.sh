#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
supported(){
 [ -x /usr/bin/zerotier-one ] && [ -x /usr/bin/zerotier-cli ] && [ -d /var/lib/zerotier-one ]
}
umask 077
case "$1" in
 probe) supported;;
 save)
  n=0
  while :;do
   SC_STORAGE_MAX_BYTES=499712 SC_STORAGE_VERIFY=1 sh "$C/starts/save_storage.sh" > "$D/zerotier-save.log" 2>&1
   rc=$?
   [ "$rc" -ne 75 ] && exit "$rc"
   n=$((n+1));[ "$n" -lt 4 ] || exit 75;sleep 2
  done;;
 start)
  # Restart only this process: firmware service commands replay stale routes.
  supported || exit 1
  set -- $(pidof zerotier-one)
  [ "$#" = 1 ] || exit 1
  pid=$1
  tr '\000' ' ' < "/proc/$pid/cmdline" | grep -qx '/usr/bin/zerotier-one /var/lib/zerotier-one ' || exit 1
  [ -s /var/lib/zerotier-one/identity.secret ] && [ -s /var/lib/zerotier-one/identity.public ] || exit 1
  : > "$D/zerotier-restart.log"
  if [ ! -f "$D/zerotier-routes-pending" ];then
   ip -o link show | awk -F': ' '$2 ~ /^zt[[:alnum:]]+$/ {print $2}' | head -c 1025 > "$D/zerotier-interfaces"
   [ "$(wc -c < "$D/zerotier-interfaces")" -le 1024 ] && [ "$(wc -l < "$D/zerotier-interfaces")" -le 16 ] || exit 1
   for family in 4 6;do
    ip -"$family" route show table all | awk '/ dev zt[[:alnum:]]+( |$)/ && !/ proto kernel / && !/ table local /' | head -c 65537 > "$D/zerotier-routes-$family"
    [ "$(wc -c < "$D/zerotier-routes-$family")" -le 65536 ] && [ "$(wc -l < "$D/zerotier-routes-$family")" -le 128 ] || exit 1
   done
   : > "$D/zerotier-routes-pending"
  fi
  kill "$pid" || exit 1
  n=0
  while kill -0 "$pid" 2>/dev/null;do n=$((n+1));[ "$n" -lt 10 ] || exit 1;sleep 1;done
  /usr/bin/zerotier-one /var/lib/zerotier-one </dev/null >/dev/null 2>&1 & newpid=$!
  n=0
  while :;do
   kill -0 "$newpid" 2>/dev/null || exit 1
   ready=1
   while IFS= read -r iface;do ip addr show dev "$iface" 2>/dev/null | grep -q 'inet' || ready=0;done < "$D/zerotier-interfaces"
   [ "$ready" = 0 ] || break
   n=$((n+1));[ "$n" -lt 20 ] || exit 1;sleep 1
  done
  for family in 4 6;do
   while IFS= read -r route;do
    [ -z "$route" ] || ip -"$family" route replace $route >> "$D/zerotier-restart.log" 2>&1 || exit 1
   done < "$D/zerotier-routes-$family"
  done
  rm -f "$D/zerotier-routes-pending"
  pidof zerotier-one >/dev/null 2>&1;;
 *)exit 1;;
esac
