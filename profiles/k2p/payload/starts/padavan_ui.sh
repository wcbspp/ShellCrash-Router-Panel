#!/bin/sh
CRASHDIR=/etc/storage/ShellCrash
mkdir /tmp/padavan-shellcrash-ui.lock 2>/dev/null || exit 0
trap 'rmdir /tmp/padavan-shellcrash-ui.lock 2>/dev/null' EXIT
# Restore the original SSR page and remove any previous menu overlay.
if grep -q proxy-frame /www/Shadowsocks.asp; then
 umount /www/Shadowsocks.asp || exit 1
fi
if grep -q 'shellCrashMenuInstalled\|shellCrashAnyTLSMenu' /www/state.js; then
 umount /www/state.js || exit 1
fi
# Padavan already provides /custom -> /opt/share/www/custom.
# The unpopulated read-only /opt is overlaid only when that path is absent.
if [ ! -d /opt/share/www/custom ]; then
 if [ -n "$(ls -A /opt 2>/dev/null)" ]; then
  logger -t ShellCrash 'Custom UI path unavailable; existing /opt preserved'
  exit 1
 fi
 mkdir -p /tmp/padavan-web-opt/share/www/custom || exit 1
 mount -o bind /tmp/padavan-web-opt /opt || exit 1
fi
# Private authenticated wrapper stays outside the public Clash UI directory.
secret=$(sed -n 's/^secret=//p' "$CRASHDIR/configs/ShellCrash.cfg" | head -1)
[ -n "$secret" ] || exit 1
secret_b64=$(printf '%s' "$secret" | base64 | tr -d '\n')
cp "$CRASHDIR/padavan/AnyTLS.asp.tpl" /opt/share/www/custom/AnyTLS.asp || exit 1
chmod 600 /opt/share/www/custom/AnyTLS.asp
ln -sf "$CRASHDIR/ui/index.html" /opt/share/www/custom/AnyTLSUI.asp
ln -sf "$CRASHDIR/padavan/native-profile.js" /opt/share/www/custom/native-profile.js
ln -sf "$CRASHDIR/padavan/manager.js" /opt/share/www/custom/manager.js
ln -sf "$CRASHDIR/padavan/sites.js" /opt/share/www/custom/sites.js
ln -sf "$CRASHDIR/padavan/health.js" /opt/share/www/custom/health.js
mkdir -p /tmp/sc-admin
[ -s /tmp/sc-admin/control-token ] || head -c 32 /dev/urandom | sha256sum | cut -c 1-16 | tr -d '\n' > /tmp/sc-admin/control-token
control_token=$(cat /tmp/sc-admin/control-token)
printf '{"token_b64":"%s","control_token":"%s"}\n' "$secret_b64" "$control_token" > /opt/share/www/custom/sc-auth.asp
chmod 600 /opt/share/www/custom/sc-auth.asp
mkdir -p /tmp/sc-admin
for action in state logs memory incidents converters remoteconnection nodeprofile configprofile uploadreceipt traffic quota quotacheck; do
 verb=$action; [ "$action" != state ] || verb=status
 printf '#!/bin/sh\nexec /etc/storage/ShellCrash/starts/manage.sh %s > /tmp/sc-admin/%s.out\n' "$verb" "$action" > "/tmp/sc-$action.sh"
 chmod 700 "/tmp/sc-$action.sh"
 printf '<%% nvram_dump("sc-admin/%s.out","sc-%s.sh"); %%>\n' "$action" "$action" > "/opt/share/www/custom/sc-$action.asp"
done
printf '<%% nvram_dump("sc-admin/sub.raw",""); %%>\n' > /opt/share/www/custom/sc-subscription.asp
printf '<%% nvram_dump("sc-admin/subscription.endpoint",""); %%>\n' > /opt/share/www/custom/sc-endpoint.asp
printf '<%% nvram_dump("sc-admin/subscription-tool.log",""); %%>\n' > /opt/share/www/custom/sc-subscriptionlog.asp
printf '<%% nvram_dump("sc-admin/subscription.progress",""); %%>\n' > /opt/share/www/custom/sc-progress.asp
[ -f "$CRASHDIR/configs/policy.tsv" ] || : > "$CRASHDIR/configs/policy.tsv"
ln -sf "$CRASHDIR/configs/policy.tsv" /opt/share/www/custom/sc-policy.asp
ln -sf "$CRASHDIR/configs/fake_ip_filter.list" /opt/share/www/custom/sc-filter.asp
for action in new put fetch fetchconvert fetchpanel apply start stop restart clear cleanup memcfg rules dns policy groupmode proxymode transport cnbypass advanced corecheck coreupdate toolcheck toolupdate mirrorsave mirrorsync mirrorverify mirrortest backuplocal backupremote; do
 case "$action" in
  new|put|fetchconvert|dns|memcfg|proxymode|transport|cnbypass) argument_count=3; keep='set -- "$1" "$2"'; token_arg='$3';;
  cleanup|fetch|fetchpanel|apply|rules|policy|groupmode|advanced|corecheck|coreupdate|toolcheck|toolupdate|mirrorsave|mirrorsync|mirrorverify|mirrortest|backuplocal|backupremote) argument_count=2; keep='set -- "$1"'; token_arg='$2';;
  *) argument_count=1; keep='set --'; token_arg='$1';;
 esac
 printf '#!/bin/sh\n[ "$#" -eq %s ] || exit 1\n[ "%s" = "$(cat /tmp/sc-admin/control-token)" ] || exit 1\n%s\n' "$argument_count" "$token_arg" "$keep" > "/tmp/sc-$action.sh"
 case "$action" in
  new|put) printf 'exec /etc/storage/ShellCrash/starts/manage.sh %s "$@"\n' "$action" >> "/tmp/sc-$action.sh";;
  *) printf '/etc/storage/ShellCrash/starts/manage.sh %s "$@" </dev/null >/dev/null 2>&1 &\n' "$action" >> "/tmp/sc-$action.sh";;
 esac
 chmod 700 "/tmp/sc-$action.sh"
done
cat /www/state.js "$CRASHDIR/padavan/nav.js" > /tmp/padavan-shellcrash-state.js || exit 1
mount -o bind /tmp/padavan-shellcrash-state.js /www/state.js || exit 1
rm -f /opt/share/www/custom/sc-probe.asp
