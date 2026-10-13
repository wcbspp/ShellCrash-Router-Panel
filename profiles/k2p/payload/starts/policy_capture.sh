#!/bin/sh
# Domain overrides and imported rules must reach the core before country-IP decisions.
# Keep ShellCrash's configured optimization for basic node-only setups.
policy_capture_apply(){
 [ -s "$C/configs/policy.tsv" ] || [ -s "$C/configs/native-profile" ] || return 0
 for table in nat mangle;do
  case "$table" in nat) chains='shellcrash shellcrash_out';; mangle) chains='shellcrash_mark shellcrash_mark_out';; esac
  for chain in $chains;do
   iptables -t "$table" -S "$chain" >/dev/null 2>&1 || continue
   while iptables -t "$table" -D "$chain" -m set --match-set cn_ip dst -j RETURN 2>/dev/null;do :;done
   if iptables -t "$table" -S "$chain" 2>/dev/null | grep -q -- '--match-set cn_ip dst -j RETURN';then return 1;fi
  done
 done
 return 0
}
