# Reject incomplete, malformed, private and non-canonical IPv4 rule feeds.
{gsub(/\r/, ""); if ($0 ~ /^[[:space:]]*$/) next
 if ($0 !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) {bad=1; next}
 split($0,c,"/"); split(c[1],a,"."); p=c[2]+0
 for(i=1;i<=4;i++) if(a[i]+0>255 || length(a[i])>3) bad=1
 if(p<8 || p>32 || a[1]==0 || a[1]==10 || a[1]==127 || a[1]>=224 || (a[1]==169&&a[2]==254) || (a[1]==172&&a[2]>=16&&a[2]<=31) || (a[1]==192&&a[2]==168)) bad=1
 address=((a[1]*256+a[2])*256+a[3])*256+a[4]; block=2^(32-p)
 if(address%block!=0) bad=1
 v=sprintf("%d.%d.%d.%d/%d",a[1],a[2],a[3],a[4],p)
 if(!seen[v]++){print v; n++; total+=block}
}
END{if(bad || n<2000 || n>10000 || total<10000000 || total>1000000000) exit 1}
