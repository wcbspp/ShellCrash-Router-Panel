# Narrow JSON array scanner for the existing single-line route/outbounds fields.
function scan(s,start,    i,j,c,str,esc,depth,brace,objstart,n,size,base,chunk,width){
 delete arr;arrayend=0;str=esc=depth=brace=n=0;size=length(s)
 # BusyBox substr() may walk UTF-8 prefixes. Scan small chunks and extract
 # complete objects once, instead of repeatedly copying a large CN-IP object.
 for(base=start;base<=size;base+=width){
  chunk=substr(s,base,1024);width=length(chunk)
  for(j=1;j<=width;j++){
   i=base+j-1;c=substr(chunk,j,1)
   if(str){if(esc)esc=0;else if(c=="\\")esc=1;else if(c=="\"")str=0;continue}
   if(c=="\""){str=1;continue}
   if(c=="[")depth++
   if(c=="]"){depth--;if(!depth){arrayend=i;return n}}
   if(c=="{"){if(!brace)objstart=i;brace++}
   if(c=="}"){brace--;if(!brace)arr[++n]=substr(s,objstart,i-objstart+1)}
  }
 }return -1
}
function preset(d){
 if(d=="google.com"||d=="gstatic.com"||d=="googleapis.com")return "分流/谷歌"
 if(d=="chatgpt.com"||d=="openai.com"||d=="oaistatic.com"||d=="oaiusercontent.com")return "分流/ChatGPT"
 if(d=="claude.ai"||d=="anthropic.com"||d=="perplexity.ai"||d=="poe.com")return "分流/国外 AI"
 if(d=="github.com"||d=="githubusercontent.com"||d=="githubassets.com")return "分流/GitHub"
 return ""
}
BEGIN{
 if(metadata=="")metadata=compiled ".tsv"
 while((getline l < oldfile)>0)old[l]=1;close(oldfile)
 n=0;while((getline l < input)>0){
  if(++n>32||split(l,f,"\t")!=3)exit 1
  k=f[1];d=f[2];t=f[3]
  if((k!="exact"&&k!="suffix")||length(d)>253||d!~/^[a-z0-9.-]+$/||d!~/\./||d~/\.\./||d~/^\./||d~/\.$/||t==""||length(t)>256||t~/["\\,\[\]\r]/||t=="GLOBAL"||t=="DIRECT"||seen[k ":" d]++)exit 1
  parts=split(d,labels,".");for(j=1;j<=parts;j++)if(length(labels[j])>63||labels[j]!~/^[a-z0-9]/||labels[j]!~/[a-z0-9]$/)exit 1
  kind[n]=k;domain[n]=d;target[n]=t;rule[n]="{\"" (k=="exact"?"domain":"domain_suffix") "\":[\"" d "\"],\"outbound\":\"" t "\"}"
 }close(input);newcount=n
}
/^"outbounds":/{
 n=scan($0,index($0,"["));if(n<0)exit 1
 finish=arrayend;members="";body=""
 for(i=1;i<=n;i++){
  o=arr[i];tag=o;sub(/^.*"tag":"/,"",tag);sub(/".*$/,"",tag)
  if(o~/"type":"(selector|urltest|direct)"/||o~/"server":"/){valid[tag]=1;if(tag!~/^分流\//&&tag!="GLOBAL"&&tag!="DIRECT")members=members sprintf("%s\"%s\"",members!=""?",":"",tag)}
  if(tag~/^分流\//){existing[tag]=o;continue}
  body=body sprintf("%s%s",body!=""?",":"",o)
 }
 valid["direct"]=1;for(j=1;j<=newcount;j++){if(!valid[target[j]])exit 1;g=kind[j]=="suffix"?preset(domain[j]):"";if(g!=""){counts[g]++;if(chosen[g]!=""&&chosen[g]!=target[j])exit 1;chosen[g]=target[j]}}
 for(g in counts){need=(g=="分流/谷歌"||g=="分流/GitHub")?3:4;if(counts[g]!=need)continue;t=chosen[g];if(t~/^分流\//&&t!=g)exit 1
  if(t==g){if(existing[g]=="")exit 1;o=existing[g];sub(/"outbounds":\[[^]]*\]/,"\"outbounds\":[" members "]",o)}
  else o="{\"type\":\"selector\",\"tag\":\"" g "\",\"outbounds\":[" members "],\"default\":\"" t "\"}"
  existing[g]=o
  for(j=1;j<=newcount;j++)if(kind[j]=="suffix"&&preset(domain[j])==g){target[j]=g;rule[j]="{\"domain_suffix\":[\"" domain[j] "\"],\"outbound\":\"" g "\"}"}
 }
 for(g in existing)body=body "," existing[g]
 for(j=1;j<=newcount;j++)print kind[j] "\t" domain[j] "\t" target[j] > metadata
 close(metadata)
 print substr($0,1,index($0,"[")) body substr($0,finish)
 checked=1;next
}
/^"route":/{
 if(!checked)exit 1
 start=index($0,"\"rules\":[");if(!start)exit 1;start+=8
 n=scan($0,start);if(n<0)exit 1;endpos=arrayend
 safe=rest="";for(i=1;i<=n;i++)if(!old[arr[i]]){
  if(arr[i]~/"action":"(hijack-dns|sniff)"/||arr[i]~/"ip_is_private":true/||arr[i]~/"clash_mode":"(Direct|Global)"/)safe=safe arr[i] ",";else rest=rest arr[i] ","
 }
 custom="";for(i=1;i<=newcount;i++){custom=custom rule[i] ",";print rule[i]>compiled}close(compiled)
 body=safe custom rest;sub(/,$/,"",body)
 print substr($0,1,start) body substr($0,endpos);found++;next
}
{print}
END{if(found!=1||!checked)exit 1}
