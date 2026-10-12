# Canonical panel profiles store each top-level field on one line.
BEGIN {n=0}
/^"route":/ {
 n++
 if ($0 !~ /"rule_set"[ ]*:[ ]*\[[ ]*"cn"[ ]*\]/) {
  if ($0 ~ /"rules"[ ]*:[ ]*\[[ ]*\]/) sub(/"rules"[ ]*:[ ]*\[[ ]*\]/,"\"rules\":[{\"rule_set\":[\"cn\"],\"outbound\":\"direct\"}]")
  else sub(/"rules"[ ]*:[ ]*\[/,"\"rules\":[{\"rule_set\":[\"cn\"],\"outbound\":\"direct\"},")
 }
 if ($0 !~ /"tag"[ ]*:[ ]*"cn"/) {
  library="{\"type\":\"local\",\"tag\":\"cn\",\"format\":\"binary\",\"path\":\"/tmp/ShellCrash/ruleset/cn.srs\"}"
  if ($0 ~ /"rule_set"[ ]*:[ ]*\[[ ]*\]/) sub(/"rule_set"[ ]*:[ ]*\[[ ]*\]/,"\"rule_set\":["library"]")
  else if ($0 ~ /"rule_set"[ ]*:[ ]*\[[ ]*\{/) sub(/"rule_set"[ ]*:[ ]*\[[ ]*\{/,"\"rule_set\":["library",{")
  else sub(/^"route":[ ]*\{/,"\"route\":{\"rule_set\":["library"],")
 }
 if ($0 !~ /"clash_mode"[ ]*:[ ]*"Direct"/) {
  modes="{\"inbound\":\"dns-in\",\"action\":\"hijack-dns\"},{\"ip_is_private\":true,\"outbound\":\"direct\"},{\"clash_mode\":\"Direct\",\"outbound\":\"direct\"},{\"clash_mode\":\"Global\",\"outbound\":\"GLOBAL\"}"
  if ($0 ~ /"rules"[ ]*:[ ]*\[[ ]*\]/) sub(/"rules"[ ]*:[ ]*\[[ ]*\]/,"\"rules\":["modes"]")
  else sub(/"rules"[ ]*:[ ]*\[/,"\"rules\":["modes",")
 }
}
/^"dns":/ {
 if ($0 !~ /"clash_mode"[ ]*:[ ]*"Direct"/) sub(/"rules"[ ]*:[ ]*\[/,"\"rules\":[{\"clash_mode\":\"Direct\",\"server\":\"dns-direct\"},")
}
{print}
END {if(n!=1)exit 2}
