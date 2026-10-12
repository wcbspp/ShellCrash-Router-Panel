# Reuse the bounded array scanner from group_mode.awk.
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
function automatic(o){gsub(/,"default":"[^"\\]*"/,"",o);gsub(/,"url":"[^"\\]*"/,"",o);gsub(/,"interval":"[^"\\]*"/,"",o);gsub(/,"tolerance":[0-9]+/,"",o);sub(/"type":"(selector|urltest)"/,"\"type\":\"urltest\"",o);sub(/}$/,",\"url\":\"https://www.google.com/generate_204\",\"interval\":\"10m\",\"tolerance\":50}",o);return o}
/^"outbounds":/{start=index($0,"[");n=scan($0,start);if(n<0)exit 1;finish=arrayend;nodes=regions=body="";root=0;for(i=1;i<=n;i++){o=arr[i];tag=o;sub(/^.*"tag":"/,"",tag);sub(/".*$/,"",tag);tags[i]=tag;if(o~/"server":/){nodes=nodes sprintf("%s\"%s\"",nodes!=""?",":"",tag)}if(tag~/^地区\//&&o~/"type":"(selector|urltest)"/){regions=regions sprintf("%s\"%s\"",regions!=""?",":"",tag);arr[i]=automatic(o)}if(tag==main&&o~/"type":"selector"/)root=i}if(!root||nodes=="")exit 1;members="\"自动选择\",\"手动选择\"";if(regions!="")members=members "," regions;sub(/"outbounds":\[[^]]*\]/,"\"outbounds\":[" members "]",arr[root]);for(i=1;i<=n;i++){if(tags[i]=="手动选择"||tags[i]=="自动选择")continue;body=body sprintf("%s%s",body!=""?",":"",arr[i])}body=body ",{\"type\":\"selector\",\"tag\":\"手动选择\",\"outbounds\":[" nodes "]},{\"type\":\"urltest\",\"tag\":\"自动选择\",\"outbounds\":[" (regions!=""?regions:nodes) "],\"url\":\"https://www.google.com/generate_204\",\"interval\":\"10m\",\"tolerance\":50}";print substr($0,1,start) body substr($0,finish);seen++;next}
{print}END{if(seen!=1)exit 1}
