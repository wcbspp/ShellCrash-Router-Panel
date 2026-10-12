#!/bin/sh
# Optional UI cache; proxy startup and supervision never depend on this script.
set -eu
C=${1:?project directory required}
kind=${2:-singbox}
case "$kind" in
 meta) package=meta_yacd;expected=05dccb1a756f8029cb2b7c70f90852390ae5cbe6093e888f1a9f68d3b122ee1e;;
 singbox) package=yacd;expected=0ac2eeba96d5974269b2444a8ffc75b74eb4a3fbb82e8b1a4d6fa192dfd32dec;;
 *) exit 2;;
esac
R=/tmp/ShellCrash-dashboard
if [ "$(cat "$R/.ready" 2>/dev/null || true)" = "$expected" ]; then
 cp "$C/ui/dashboard-bridge.js" "$R/dashboard-bridge.js"
 exit 0
fi
avail=$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo)
[ "${avail:-0}" -ge 20000 ] || { echo '可用内存不足 20 MB，暂缓下载高级面板';exit 1; }
mkdir /tmp/sc-dashboard-install.lock 2>/dev/null || exit 1
trap 'rm -rf /tmp/sc-dashboard-install.lock /tmp/sc-dashboard-stage /tmp/sc-dashboard.tar.gz' EXIT
W=/tmp/sc-dashboard-install.lock
T=$C;[ "$C" != /data/ShellCrash ] || T=/data/ShellCrash-tool
# Resolve the source selected by ShellCrash without invoking its installer.
(set +u;export CRASHDIR="$T" TMPDIR="$W"; . "$T/configs/ShellCrash.cfg";[ ! -f "$T/configs/command.env" ] || . "$T/configs/command.env";. "$T/libs/web_get_bin.sh";webget(){ printf '%s\n' "$2" > "$W/tool-url"; };get_bin "$W/unused" "bin/dashboard/$package.tar.gz") 2>/dev/null || true
ca='';if [ "$C" != /data/ShellCrash ];then cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$W/ca.pem" 2>/dev/null || true;ca=$W/ca.pem;fi
. "$C/starts/remote.sh"
mirror=$(sed -n 's/^base=//p' "$C/configs/mirror.conf" 2>/dev/null | head -1 || true)
remote_ready || mirror=''
[ "$(remote_transport)" != webdav ] || mirror=''
{
 [ ! -s "$W/tool-url" ] || cat "$W/tool-url"
 printf '%s\n' "https://raw.githubusercontent.com/juewuy/ShellCrash/16b4ab5bf164dba5e933db792d741a54e37a7491/bin/dashboard/$package.tar.gz"
 [ -z "$mirror" ] || printf '%s\n' "$mirror/dashboard-$expected.tar.gz"
} > "$W/urls"
found=0;attempt=0
if remote_fetch dashboard "$expected" tar.gz /tmp/sc-dashboard.tar.gz 1048576;then found=1;echo "高级面板：远程备份已校验";fi
while IFS= read -r url;do
 [ "$found" != 1 ] || break
 attempt=$((attempt+1));case "$url" in https://*|http://*) :;;*)continue;;esac
 echo "高级面板下载：尝试源 $attempt"
 if curl -4 ${ca:+--cacert "$ca"} --noproxy '*' -fsSL --connect-timeout 5 --max-time 20 --max-filesize 1048576 "$url" -o /tmp/sc-dashboard.tar.gz;then
  if command -v sha256sum >/dev/null 2>&1;then actual=$(sha256sum /tmp/sc-dashboard.tar.gz | cut -d ' ' -f1);else actual=$(openssl dgst -sha256 /tmp/sc-dashboard.tar.gz | awk '{print $NF}');fi
  if [ "$actual" = "$expected" ];then found=1;echo "高级面板文件校验通过：源 $attempt";break;fi
  echo '下载文件校验不符，尝试下一个源'
 fi
done < "$W/urls"
[ "$found" = 1 ] || { echo '三个来源均不可用，轻量面板和代理服务保持运行';exit 1; }
if remote_ready && ! remote_has dashboard "$expected" tar.gz;then
 if ! remote_put dashboard /tmp/sc-dashboard.tar.gz tar.gz >/dev/null;then echo '高级面板可用；远程备份待重试';fi
fi
mkdir -p /tmp/sc-dashboard-stage
tar -zxf /tmp/sc-dashboard.tar.gz -C /tmp/sc-dashboard-stage
[ -s /tmp/sc-dashboard-stage/index.html ]
sed 's@<head>@<head><style>a[href="#/configs"],a[href="#/config"],a[href="#/logs"],a[href="#/home"],a[href="#/"]{display:none!important}</style><script src="./dashboard-bridge.js"></script>@;s@http://127.0.0.1:9090@http://shellcrash.invalid@g;s@<script id="vite-plugin-pwa:register-sw"[^<]*</script>@@' /tmp/sc-dashboard-stage/index.html > /tmp/sc-dashboard-stage/index.new
mv /tmp/sc-dashboard-stage/index.new /tmp/sc-dashboard-stage/index.html
cp "$C/ui/dashboard-bridge.js" /tmp/sc-dashboard-stage/dashboard-bridge.js
rm -f /tmp/sc-dashboard-stage/sw.js /tmp/sc-dashboard-stage/registerSW.js
printf '%s\n' "$expected" > /tmp/sc-dashboard-stage/.ready
rm -rf "$R";mv /tmp/sc-dashboard-stage "$R"
