# Padavan binds the authenticated core API to its LAN address. Native readiness
# runs before fw_start and must not hang on the firmware's loopback INPUT drop.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || return 1
sc_wait_rule=0
if ! iptables -C INPUT -i lo -d "$PANEL_LAN_IP" -p tcp --dport "$db_port" -j ACCEPT 2>/dev/null; then
 if iptables -I INPUT 1 -i lo -d "$PANEL_LAN_IP" -p tcp --dport "$db_port" -j ACCEPT; then sc_wait_rule=1; fi
fi
i=0
test=''
while [ -z "$test" ] && [ "$i" -lt 30 ]; do
 if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:${db_port}/version" 2>/dev/null | grep -q '"version"'; then
  test=ready
 else
  sleep 1
 fi
 i=$((i+1))
done
if [ "$sc_wait_rule" = 1 ]; then
 iptables -D INPUT -i lo -d "$PANEL_LAN_IP" -p tcp --dport "$db_port" -j ACCEPT 2>/dev/null || :
fi
unset sc_wait_rule
