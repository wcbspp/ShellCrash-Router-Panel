i=1
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
while [ -z "$test" -a "$i" -lt 30 ]; do
	sleep 1
	if curl --version >/dev/null 2>&1; then
		test=$(curl -s -H "Authorization: Bearer $secret" http://${PANEL_LAN_IP}:${db_port}/proxies | grep -o proxies)
	else
		test=$(wget -q --header="Authorization: Bearer $secret" -O - http://${PANEL_LAN_IP}:${db_port}/proxies | grep -o proxies)
	fi
	i=$((i + 1))
done
