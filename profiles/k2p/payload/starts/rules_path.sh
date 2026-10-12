#!/bin/sh
# Import once into persistent ShellCrash storage; never depend on an SSR directory.
rules_ensure(){
 RULES_FILE="$C/configs/cn_ip.txt"
 mkdir -p "$C/configs"
 imported=0
 tmp="$C/configs/cn_ip.pending"
 if [ -s "$RULES_FILE" ] && [ "$(wc -c < "$RULES_FILE")" -le 262144 ] && awk -f "$C/starts/rules_validate.awk" "$RULES_FILE" > "$tmp"; then
  rm -f "$tmp"
 else
  rm -f "$tmp"
  imported=0
  for source in "${PANEL_CN_IP_FILE:-}" /etc/storage/chinadns/chnroute.txt "$C/cn_ip.txt" "$C/configs/cn_ip.default.txt"; do
   [ -s "$source" ] || continue
   [ "$(wc -c < "$source")" -le 262144 ] || continue
   if awk -f "$C/starts/rules_validate.awk" "$source" > "$tmp"; then
    mv "$tmp" "$RULES_FILE"; imported=1; break
   fi
   rm -f "$tmp"
  done
  [ "$imported" = 1 ] || { logger -t ShellCrash 'No valid domestic IP table; reinstall the bundled rules'; return 1; }
  # Keep the core's embedded table aligned with the persistent firewall table.
  if [ -s "$C/jsons/config.json" ]; then
   awk 'FNR==NR{a=a sep "\"" $0 "\"";sep=",";next}
    /^"route":/{if(gsub(/"ip_cidr":\[[^]]*\]/,"\"ip_cidr\":[" a "]")!=1)bad=1;found++}
    {print} END{if(bad||found!=1)exit 1}' "$RULES_FILE" "$C/jsons/config.json" > "$C/jsons/rules.pending" || { rm -f "$C/jsons/rules.pending"; return 1; }
   mv "$C/jsons/rules.pending" "$C/jsons/config.json"
  fi
 fi
 if [ ! -s "$C/configs/rules.meta" ] || { [ "$imported" = 1 ] && [ "$(sed -n '3p' "$C/configs/rules.meta")" != "$(sha256sum "$RULES_FILE" | awk '{print $1}')" ]; }; then
  { wc -l < "$RULES_FILE" | tr -d ' '; printf '本地预置 / 已导入\n'; sha256sum "$RULES_FILE" | awk '{print $1}'; } > "$C/configs/rules.meta"
 fi
 chmod 600 "$RULES_FILE" "$C/configs/rules.meta"
 return 0
}
