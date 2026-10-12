# Read public settings without sourcing ShellCrash.cfg or exposing subscription secrets.
function escape(v){gsub(/\\/,"\\\\",v);gsub(/"/,"\\\"",v);gsub(/\t/,"\\t",v);gsub(/\r/,"\\r",v);return v}
function str(v){return "\"" escape(v) "\""}
BEGIN {
 while((getline line < cfgfile)>0){
  if(line !~ /^[A-Za-z_][A-Za-z_0-9]*=/)continue
  k=line;sub(/=.*/,"",k);v=line;sub(/^[^=]*=/,"",v);sub(/\r$/,"",v)
  q=substr(v,1,1);if((q=="\047"||q=="\"")&&substr(v,length(v),1)==q)v=substr(v,2,length(v)-2)
  cfg[k]=v
 }
 close(cfgfile)
 printf "{\"servers\":["
}
/^[34][0-9][0-9][[:space:]]/ {
 s++;sn[s]=$2;su[s]=$3;if(substr($1,1,1)=="4")four++
 if(s<=8){if(s>1)printf ",";printf "{\"id\":%d,\"name\":%s,\"url\":%s}",s,str($2),str($3)}
}
/^5[0-9][0-9][[:space:]]/ && t<100 {t++;tn[t]=$2;tu[t]=$3}
END {
 printf "],\"templates\":["
 for(i=1;i<=t;i++){if(i>1)printf ",";printf "{\"name\":%s,\"url\":%s}",str(tn[i]),str(tu[i])}
 
 n=cfg["server_link"]==""?1:cfg["server_link"]+0;if(n<1||n>four||int(n)!=n)n=1
 rule=cfg["rule_link"]==""?1:cfg["rule_link"]+0;if(rule<1||rule>t||int(rule)!=rule)rule=1
 ua=cfg["user_agent"];mode=(ua==""||ua=="auto")?"auto":ua=="none"?"none":"custom"
 kind="singbox";core=cfg["core_v"]==""?"1.12.13":cfg["core_v"]
 if(mode=="auto")ua="sing-box/singbox/" core;else if(mode=="none")ua=""
 printf "],\"defaults\":{\"core_kind\":%s,\"core_version\":%s,\"ua_mode\":%s,\"ua\":%s,\"server_index\":%d,",str(kind),str(core),str(mode),str(ua),n
 printf "\"converter\":{\"name\":%s,\"url\":%s},\"template\":{\"name\":%s,\"url\":%s},",str(sn[n]),str(su[n]),str(tn[rule]),str(tu[rule])
 printf "\"include\":%s,\"exclude\":%s,\"target\":\"singbox\",\"parameters\":\"insert=true · new_name=true · scv=true · udp=true\"}}\n",str(cfg["include"]),str(cfg["exclude"])
}
