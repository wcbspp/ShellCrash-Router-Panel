function quote(s){gsub(/\\/,"\\\\",s);gsub(/\"/,"\\\"",s);return "\"" s "\""}
{gsub(/\r/,"");sub(/^[[:space:]]+/,"");sub(/[[:space:]]+$/,"")
 if($0==""||$0~/^#/)next
 if($0=="Mijia Cloud")next
 v=tolower($0)
 if(length(v)>253||v!~/^[a-z0-9_.*+-]+$/||v~/\.\./||v!~/\./){bad=1;next}
 if(seen[v]++)next
 n++
 if(v~/^\+\./&&substr(v,3)!~/[+*]/){su=su sp quote(substr(v,3));sp=",";next}
 if(v!~/[+*]/){de=de dp quote(v);dp=",";next}
 prefix="^";if(v~/^\+\./){v=substr(v,3);prefix="(^|\\.)"}
 r="";for(i=1;i<=length(v);i++){c=substr(v,i,1);q=(c=="."?"\\.":c=="*"?"[^.]+":c);r=r q}
 re=re rp quote(prefix r "$");rp=","
}
END{if(bad||n>512)exit 1;printf "{\"domain\":[%s],\"domain_suffix\":[%s],\"domain_regex\":[%s]}\n",de,su,re}
