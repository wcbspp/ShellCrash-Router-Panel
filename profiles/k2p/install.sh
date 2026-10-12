#!/bin/sh
# Padavan ShellCrash panel overlay installer. SPDX-License-Identifier: GPL-3.0-only
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
BASE=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
C=/etc/storage/ShellCrash
V="$BASE/vendor/ShellCrash-1.9.4"
fresh=0
[ -e "$C" ] || fresh=1
mode=${1:---check}; shift || :
profile=''; secret_file=''; subscription_file=''; core_file=''
while [ "$#" -gt 0 ]; do
 case "$1" in --core-file) core_file=$2; shift 2;; --profile) profile=$2; shift 2;; --secret-file) secret_file=$2; shift 2;; --subscription-file) subscription_file=$2; shift 2;; *) echo "未知参数: $1"; exit 1;; esac
done
[ "$mode" = --check ] || [ "$mode" = --install ] || { echo '用法: sh install.sh --check | --install --profile FILE --secret-file FILE'; exit 1; }
[ "$(id -u)" = 0 ] || { echo '需要路由器SSH管理员权限'; exit 1; }
for cmd in nvram curl iptables ipset bzip2 sha256sum mtd_write mount stat awk tar base64 crontab; do command -v "$cmd" >/dev/null || { echo "缺少依赖: $cmd"; exit 1; }; done
[ -f /www/state.js ] && [ -f /sbin/mtd_storage.sh ] || { echo '仅支持已配置的Padavan'; exit 1; }
[ "$fresh" = 0 ] && framework="$C" || framework="$V"
[ -f "$framework/version" ] && grep -q '^1\.9\.4' "$framework/version" || { echo '此版本适配ShellCrash 1.9.4，其他版本需单独验证'; exit 1; }
[ "$fresh" = 1 ] || { [ -f "$C/configs/ShellCrash.cfg" ] && grep -qx 'crashcore=singbox' "$C/configs/ShellCrash.cfg"; } || { echo '先在ShellCrash中配置sing-box'; exit 1; }
[ "$(uname -m)" = mips ] || [ "$(uname -m)" = mipsel ] || { echo '首版只验证MT7621/MIPSLE，其他架构不直接安装'; exit 1; }
[ -f "$C/configs/cn_ip.txt" ] || [ -f /etc/storage/chinadns/chnroute.txt ] || [ -f "$BASE/examples/cn_ip.default.txt" ] || { echo '缺少国内IPv4规则表'; exit 1; }
if [ "$fresh" = 1 ]; then
 printf '4f946031a0483ed528e266143d459075489cce6c3f8f2f4681f39ca6d7448681  %s\n' "$BASE/vendor/ShellCrash-1.9.4.tar.gz" | sha256sum -c - >/dev/null || { echo '原始ShellCrash包校验失败'; exit 1; }
 (cd "$V" && sha256sum -c SHA256SUMS >/dev/null) || { echo '内置ShellCrash包校验失败'; exit 1; }
fi
[ -n "$profile" ] || profile=$C/jsons/config.json
[ -s "$profile" ] && grep -q '^"outbounds":' "$profile" && grep -q '"tag":"proxy-main"' "$profile" || { echo '请先使用tools/prepare_profile.py生成单行字段配置'; exit 1; }
[ "$mode" != --install ] || [ -s "$secret_file" ] || { echo '安装时需要与profile匹配的--secret-file'; exit 1; }
[ "$(nvram get ss_enable)" != 1 ] || { echo '请先在旧SSR插件中停止服务；其设置和页面会保留'; exit 1; }
for hook in bfstart afstart; do
 [ ! -s "$C/task/$hook" ] || { echo "已有自定义钩子task/${hook}；请备份并人工合并，不自动覆盖"; exit 1; }
done
[ ! -f "$C/.start_error" ] || { echo '现有ShellCrash启动异常，先排查后安装'; exit 1; }
[ ! -f "$C/.dis_startup" ] || { echo '现有ShellCrash关闭了自启动，先确认开机策略'; exit 1; }
[ ! -e /tmp/sc-legacy-guard ] || { echo '已有本项目运行覆盖，请按升级文档处理'; exit 1; }
[ ! -d /opt/share/www/custom ] && [ -n "$(ls -A /opt 2>/dev/null)" ] && { echo '已有/opt内容且无custom网页目录，停止安装'; exit 1; }
[ -z "$subscription_file" ] || { [ -s "$subscription_file" ] && [ "$(wc -c < "$subscription_file")" -le 4096 ] && ! grep -q '[^A-Za-z0-9+/=]' "$subscription_file"; } || { echo '订阅记录格式无效'; exit 1; }
if [ -n "$core_file" ];then
 [ -s "$core_file" ] || { echo '离线内核文件不存在'; exit 1; }
 expected=$(sed -n 's/^sha256=//p' "$BASE/examples/core-installed.info")
 [ "${#expected}" = 64 ] && printf '%s  %s\n' "$expected" "$core_file" | sha256sum -c - >/dev/null || { echo '离线内核校验失败，未安装'; exit 1; }
fi
printf '预检通过；LAN=%s，目标=%s\n' "$(nvram get lan_ipaddr)" "$C"
[ "$mode" = --install ] || exit 0
[ ! -d /tmp/padavan-panel-install.lock ] || { echo '已有安装任务'; exit 1; }
mkdir /tmp/padavan-panel-install.lock
trap 'status=$?; rm -f /tmp/padavan-panel-profile.json /tmp/padavan-panel-save.sh; rmdir /tmp/padavan-panel-install.lock 2>/dev/null || :; exit "$status"' EXIT
umask 077
backup=/tmp/padavan-panel-before-install.tar.gz
# Back up affected storage before stopping the existing service.
sh "$BASE/backup.sh" "$backup"
chmod 600 "$backup"
echo "回滚备份: ${backup}（重启前用scp下载保存）"
# Stage caller input outside the directory which is about to be modified.
cp "$profile" /tmp/padavan-panel-profile.json
secret=$(tr -d '\r\n' < "$secret_file")
printf '%s' "$secret" | grep -Eq '^[A-Za-z0-9_-]{24,128}$' || { echo '管理密钥格式不正确'; exit 1; }
grep -Fq "\"secret\":\"$secret\"" /tmp/padavan-panel-profile.json || { echo '配置与管理密钥不匹配'; exit 1; }
grep -Fq "\"external_controller\":\"$(nvram get lan_ipaddr):9999\"" /tmp/padavan-panel-profile.json || { echo '配置LAN地址与路由器不一致'; exit 1; }
cp "$BASE/payload/starts/save_storage.sh" /tmp/padavan-panel-save.sh
chmod 700 /tmp/padavan-panel-save.sh
committed=0
rollback(){
 echo '安装失败，恢复安装前Storage；建议维护时重启清除运行挂载'
 CRASHDIR="$C" "$C/start.sh" stop >/dev/null 2>&1 || :
 for target in /www/state.js /sbin/mtd_storage.sh /usr/bin/update_chnroute.sh /usr/bin/update_gfwlist.sh; do
  umount "$target" >/dev/null 2>&1 || :
 done
 if crontab -l 2>/dev/null | grep -q '#ShellCrashSaveSelection'; then
  crontab -l | grep -v '#ShellCrashSaveSelection' > /tmp/sc-panel-clean.cron
  crontab /tmp/sc-panel-clean.cron
  rm -f /tmp/sc-panel-clean.cron
 fi
 sh "$BASE/restore_storage.sh" "$backup" || return 1
 /bin/sh /tmp/padavan-panel-save.sh || echo '回滚落盘失败：务必保留备份，不要断电'
 [ ! -f "$C/start.sh" ] || CRASHDIR="$C" "$C/start.sh" start >/dev/null 2>&1 || :
}
finish(){
 code=$?
 trap - EXIT HUP INT TERM
 [ "$committed" = 1 ] || rollback || :
 rm -f /tmp/padavan-panel-profile.json /tmp/padavan-panel-save.sh
 rmdir /tmp/padavan-panel-install.lock 2>/dev/null || :
 exit "$code"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
if [ "$fresh" = 0 ]; then
 CRASHDIR="$C" "$C/start.sh" stop
else
 mkdir -p "$C"
 tar -xzf "$BASE/vendor/ShellCrash-1.9.4.tar.gz" -C "$C"
 cp "$V/LICENSE.txt" "$C/LICENSE.txt"
 mkdir -p "$C/configs" "$C/jsons" "$C/task"
 printf 'crashcore=singbox\nversionsh_l=1.9.4release\nsystype=Padavan\n' > "$C/configs/ShellCrash.cfg"
fi
# Keep the router-specific cfg and upstream framework; overlay only published files.
cp -R "$BASE/payload/starts/." "$C/starts/" || exit 1
cp -R "$BASE/payload/libs/." "$C/libs/" || exit 1
cp -R "$BASE/payload/menus/." "$C/menus/" || exit 1
mkdir -p "$C/padavan" "$C/ui" "$C/task"
cp -R "$BASE/payload/padavan/." "$C/padavan/"
cp -R "$BASE/payload/ui/." "$C/ui/"
cp /tmp/padavan-panel-profile.json "$C/jsons/config.json"
[ -z "$subscription_file" ] || cp "$subscription_file" "$C/configs/subscription.url.b64"
cp "$BASE/examples/cn_ip.default.txt" "$C/configs/cn_ip.default.txt"
cp "$BASE/examples/cn_ip.default.info" "$C/configs/cn_ip.default.info"
cp "$BASE/examples/core-installed.info" "$C/configs/core-installed.info"
[ -f "$C/configs/core_mirrors.list" ] || : > "$C/configs/core_mirrors.list"
[ -f "$C/configs/panel.conf" ] || cp "$BASE/examples/panel.conf.example" "$C/configs/panel.conf"
[ -f "$C/configs/fake_ip_filter.list" ] || cp "$BASE/examples/fake_ip_filter.list" "$C/configs/fake_ip_filter.list"
cp "$BASE/examples/public-ca.pem" "$C/configs/subscription-ca.pem"
sed -i '/^secret=/d; /^core_v=/d; /^dns_mod=/d; /^disoverride=/d; /^start_old=/d; /^cpucore=/d; /^zip_type=/d; /^custcorelink=/d; /^db_port=/d; /^host=/d; /^firewall_mod=/d; /^firewall_area=/d; /^cn_ip_route=/d; /^ipv6_redir=/d; /^common_ports=/d; /^network_check=/d; /^mix_port=/d; /^redir_port=/d; /^dns_port=/d; /^redir_mod=/d' "$C/configs/ShellCrash.cfg"
{ printf 'secret=%s\n' "$secret"; printf 'core_v=1.12.13\ndns_mod=mix\ndisoverride=\nstart_old=ON\ncpucore=mipsle-softfloat\nzip_type=tar.gz\ndb_port=9999\nfirewall_mod=iptables\nfirewall_area=1\ncn_ip_route=ON\nipv6_redir=OFF\ncommon_ports=OFF\nnetwork_check=OFF\nmix_port=7890\nredir_port=7892\ndns_port=1053\nredir_mod=Redir模式\n'; printf 'host=%s\n' "$(nvram get lan_ipaddr)"; sed -n 's/^url=/custcorelink=/p' "$BASE/examples/core-installed.info"; } >> "$C/configs/ShellCrash.cfg"
cat > "$C/configs/command.env" <<'ENV'
BINDIR=/tmp/ShellCrash
TMPDIR=/tmp/ShellCrash
COMMAND="$TMPDIR/CrashCore run -D $BINDIR -C $TMPDIR/jsons"
ENV
# Preflight refused nonempty user hooks; install the verified pair.
printf '%s\n' "$C/starts/panel_bfstart.sh || exit 1" > "$C/task/bfstart"
printf '%s\n' "$C/starts/panel_afstart.sh" > "$C/task/afstart"
# Native init would start before the bootstrap download. Replace only its
# official tagged entry, retaining all unrelated startup commands.
sed -i '/#ShellCrash初始化脚本$/d; /#PadavanShellCrashPanel$/d' /etc/storage/started_script.sh
[ ! -f "$C/task/cron" ] || sed -i '/#ShellCrashSaveSelection$/d' "$C/task/cron"
printf '* * * * * /bin/sh %s/starts/save_selection.sh #ShellCrashSaveSelection\n' "$C" >> "$C/task/cron"
printf '\n%s boot & #PadavanShellCrashPanel\n' "$C/starts/panel_boot.sh" >> /etc/storage/started_script.sh
chmod 700 "$C/start.sh" "$C/menu.sh" "$C/starts/"*.sh
chmod 600 "$C/configs/panel.conf" "$C/configs/core-installed.info" "$C/configs/ShellCrash.cfg" "$C/jsons/config.json"
# Start in RAM first; save only after the core and authenticated API are healthy.
if [ -n "$core_file" ];then
 mkdir -p /tmp/ShellCrash
 cp "$core_file" /tmp/ShellCrash/CrashCore.tar.gz
fi
"$C/starts/panel_boot.sh" || exit 1
ready=0; tries=0
while [ "$tries" -lt 30 ]; do
 if curl --noproxy '*' -fsS --max-time 2 -H "Authorization: Bearer $secret" "http://$(nvram get lan_ipaddr):9999/version" >/dev/null 2>&1; then ready=1; break; fi
 sleep 2; tries=$((tries+1))
done
[ "$ready" = 1 ] || { echo '内核启动未通过验证，回滚'; exit 1; }
"$C/starts/save_storage.sh" || exit 1
committed=1
echo '安装完成：登录路由器后台 → 高级设置 → ShellCrash。请下载安装前备份。'
