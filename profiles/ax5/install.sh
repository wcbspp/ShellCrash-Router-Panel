#!/bin/sh
# Redmi AX5 RA67 1.0.105: install the verified official ShellCrash tool, then the adapter.
set -e
umask 077
source=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
C=/data/ShellCrash
T=/data/ShellCrash-tool
mode=${1:-auto}
case "$mode" in auto|--install|--update|--check) ;; *) echo '用法：sh install.sh [--install|--update|--check]';exit 2;; esac
fail(){ echo "$*" >&2;exit 1; }
[ "$(id -u)" = 0 ] || fail '请以 root 执行'
[ "$(uname -m)" = armv7l ] || fail '仅验证 ARMv7 AX5'
rom=/usr/share/xiaoqiang/xiaoqiang_version
[ -f "$rom" ] && grep -q "HARDWARE 'RA67'" "$rom" && grep -q "ROM '1.0.105'" "$rom" || fail '仅验证 RA67 原厂 1.0.105，未改变系统'
for cmd in lua curl openssl tar iptables stat;do command -v "$cmd" >/dev/null || fail "缺少依赖：$cmd";done
lua -e 'require("cjson");require("luci.http");require("nixio")' || fail 'LuCI/Lua 依赖不完整'
if [ "$mode" = auto ];then if [ -f "$C/ax5/prepare.sh" ];then mode=--update;else mode=--install;fi;fi
[ "$mode" != --check ] || { echo '固件与依赖检查通过；未写入或启动服务';exit 0; }
[ ! -d /tmp/ShellCrash/operation.lock ] || fail '面板操作正在进行，请稍后重试'
if [ "$mode" = --install ];then
 [ ! -e "$C" ] && [ ! -e "$T" ] && [ ! -e /etc/init.d/shellcrash ] && ! command -v crash >/dev/null 2>&1 || fail '检测到已有 ShellCrash，请先按迁移说明处理；没有覆盖配置'
else
 [ -s "$C/configs/config.json" ] && [ -f "$C/ax5/prepare.sh" ] && [ -f "$T/start.sh" ] || fail '未发现本项目完整部署，不能按更新方式覆盖'
fi
available=$(df -k /data | awk 'END{print $4}')
need=16000
if [ "$mode" = --update ];then
 largest=$(find "$source/ax5" "$source/ui" -type f -exec stat -c %s {} \; | awk '$1>largest{largest=$1} END{print largest+0}')
 need=$(( (largest+1023)/1024 + 256 ))
fi
[ "$available" -ge "$need" ] || fail "持久空间不足：需至少 $need KB，可用 $available KB"
[ "$(df -k /overlay | awk 'END{print $4}')" -ge 256 ] || fail 'overlay 空间不足'
mem=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
mem_need=24000;[ "$mode" != --update ] || mem_need=16384
[ "${mem:-0}" -ge "$mem_need" ] || fail "可用内存不足：此操作需要 $mem_need KB，请稍后重试"
mkdir -p /tmp/ShellCrash
mkdir /tmp/ShellCrash/operation.lock || fail '已有操作在进行'
date +%s > /tmp/ShellCrash/operation.lock.time
if [ "$mode" = --update ];then stage=$(mktemp -d /tmp/ax5-source.XXXXXX);else stage=$(mktemp -d /data/.shellcrash-install.XXXXXX);fi
committed=0
rollback='';pending=''
cleanup(){
 rc=$?
 [ -z "$pending" ] || rm -f "$pending"
 if [ "$rc" != 0 ] && [ -n "$rollback" ];then tar -xzf "$rollback" -C / || echo '源码回退失败，请使用缓存备份恢复' >&2;fi
 if [ "$rc" != 0 ] && [ "$committed" = 1 ] && [ "$mode" = --install ];then
  /etc/init.d/shellcrash stop 2>/dev/null || true
  /etc/init.d/shellcrash disable 2>/dev/null || true
  cp "$stage/header-before.htm" /usr/lib/lua/luci/view/web/inc/header.htm
  crontab "$stage/cron-before"
  rm -f /etc/init.d/shellcrash /usr/bin/crash /usr/lib/lua/luci/controller/web/shellcrash.lua /usr/lib/lua/luci/view/web/shellcrash.htm
  rm -rf "$C" "$T"
  echo '首次安装失败，已撤销本次新增服务与目录' >&2
 fi
 rm -rf "$stage";rmdir /tmp/ShellCrash/operation.lock 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir -p "$stage/panel"
cp -r "$source/ax5" "$source/ui" "$stage/panel/"
find "$stage/panel/ax5" -name '*.sh' -exec chmod 755 {} \;
for file in "$stage/panel/ax5/"*.sh;do sh -n "$file";done
lua - "$stage/panel" <<'LUA'
for name in io.popen('ls '..arg[1]..'/ax5/*.lua'):lines()do assert(loadfile(name))end
LUA
if [ "$mode" = --install ];then
 echo '1/3 安装已验证的官方 ShellCrash 1.9.4release'
 hash=$(openssl dgst -sha256 "$source/vendor/ShellCrash-1.9.4.tar.gz" | awk '{print $NF}')
 [ "$hash" = 4f946031a0483ed528e266143d459075489cce6c3f8f2f4681f39ca6d7448681 ] || fail '工具安装包校验失败'
 cp /usr/lib/lua/luci/view/web/inc/header.htm "$stage/header-before.htm"
 crontab -l > "$stage/cron-before" 2>/dev/null || :
 mkdir -p "$stage/tool/configs" "$stage/panel/configs" "$stage/panel/cache" "$stage/panel/ruleset"
 tar -xzf "$source/vendor/ShellCrash-1.9.4.tar.gz" -C "$stage/tool"
 cp "$source/vendor/servers.list" "$stage/tool/configs/"
 cp "$source/examples/cn.srs" "$source/examples/cn.mrs" "$stage/panel/ruleset/"
 lua "$source/tools/prepare-install.lua" "$source" "$stage"
 echo '2/3 从 ShellCrash 固定工具源下载 sing-box 1.12.13'
 origin=https://raw.githubusercontent.com/juewuy/ShellCrash/21734eca91ec7a540494a5f43eac485403c18dac/bin/singbox/singbox-linux-armv7.tar.gz
 cdn=https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@21734eca91ec7a540494a5f43eac485403c18dac/bin/singbox/singbox-linux-armv7.tar.gz
 archive=$stage/panel/cache/core-armv7.tar.gz
 if [ -n "${SC_OFFLINE_CORE:-}" ];then
  [ -s "$SC_OFFLINE_CORE" ] || fail '离线内核文件不存在'
  cp "$SC_OFFLINE_CORE" "$archive"
 else
 curl -4 -fsSL --connect-timeout 5 --max-time 120 --max-filesize 12000000 "$cdn" -o "$archive" || curl -4 -fsSL --connect-timeout 5 --max-time 120 --max-filesize 12000000 "$origin" -o "$archive"
 fi
 hash=$(openssl dgst -sha256 "$archive" | awk '{print $NF}')
 [ "$hash" = 40d97dc43df35d326916d488f748371e2e773a59569c01e23330081274ebf65b ] || fail '内核包校验失败，未安装'
 printf '%s\n' "$hash" > "$stage/panel/cache/core.sha256"
 printf 'KIND=singbox\nVERSION=1.12.13\nHASH=%s\nSOURCE=%s\n' "$hash" "$origin" > "$stage/panel/cache/core.env"
 mkdir -p "$stage/check"
 tar -xzf "$archive" -C "$stage/check" CrashCore
 chmod 700 "$stage/check/CrashCore"
 sed "s#/data/ShellCrash/ruleset/cn.srs#$stage/panel/ruleset/cn.srs#g" "$stage/panel/configs/config.json" > "$stage/check/config.json"
 GOMEMLIMIT=12MiB GOGC=25 "$stage/check/CrashCore" check -D "$stage/check" -c "$stage/check/config.json"
 rm -rf "$stage/check"
 mv "$stage/tool" "$T";mv "$stage/panel" "$C";committed=1
else
 echo '更新页面与适配源码，保留订阅、内核、规则和 ZeroTier'
 rollback=$stage/code-before.tar.gz
 tar -czf "$rollback.new" -C / data/ShellCrash/ax5 data/ShellCrash/ui etc/init.d/shellcrash usr/lib/lua/luci/controller/web/shellcrash.lua usr/lib/lua/luci/view/web/shellcrash.htm usr/lib/lua/luci/view/web/inc/header.htm usr/bin/crash
 mv "$rollback.new" "$rollback"
 for part in ax5 ui;do
  find "$stage/panel/$part" -type f > "$stage/files"
  while IFS= read -r file;do
   relative=${file#"$stage/panel/$part/"};target=$C/$part/$relative
   mkdir -p "$(dirname "$target")"
   pending=$target.sc-new.$$
   cp -p "$file" "$pending"
   mv "$pending" "$target"
   pending=''
  done < "$stage/files"
 done
fi
echo '3/3 接入小米管理菜单'
cp "$C/ax5/controller.lua" /usr/lib/lua/luci/controller/web/shellcrash.lua
cp "$C/ax5/view.htm" /usr/lib/lua/luci/view/web/shellcrash.htm
cp "$C/ax5/shellcrash.init" /etc/init.d/shellcrash
chmod 755 /etc/init.d/shellcrash
lua "$source/tools/menu-install.lua"
"$C/ax5/tool-sync.sh"
/etc/init.d/shellcrash enable
# A source-only update does not stop or restart the running proxy.
if [ "$mode" = --install ];then
 (crontab -l 2>/dev/null | sed '/#SC_AX5/d';echo '* * * * * lua /data/ShellCrash/ax5/state.lua sample #SC_AX5') | crontab -
 /etc/init.d/shellcrash start
 for n in 1 2 3 4 5 6 7 8 9 10 11 12;do
  if lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()>0 and M.api("/version")~="" and 0 or 1)';then break;fi;sleep 1
 done
 lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()>0 and M.api("/version")~="" and 0 or 1)' || fail '内核启动检查失败'
fi
if [ "$mode" = --update ];then
 cp "$rollback" /tmp/ShellCrash/panel-source-before.tar.gz
 chmod 600 /tmp/ShellCrash/panel-source-before.tar.gz
 echo '本次源码回退包：/tmp/ShellCrash/panel-source-before.tar.gz（仅 RAM，重启前保存到电脑）'
fi
rollback=''
sync
if [ "$mode" = --install ];then echo '完成。首次安装为真实 DNS、全直连；在小米管理页打开 ShellCrash，填写自己的订阅。';else echo '源码更新完成，配置和当前代理保持。刷新小米管理页即可。';fi
