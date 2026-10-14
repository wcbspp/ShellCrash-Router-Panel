function library(){return "{\"type\":\"local\",\"tag\":\"panel-cn-ip\",\"format\":\"source\",\"path\":\"" asset "\"}"}
# Canonical single-line JSON fields, no evaluation of subscription strings.
# Arrays are scanned in bounded chunks to avoid quadratic BusyBox UTF-8 substr.
function field(s,key,    base,chunk,width,j,i,c,depth,str,esc,word,start){
 depth=str=esc=0
 for(base=1;base<=length(s);base+=width){
  chunk=substr(s,base,1024);width=length(chunk)
  for(j=1;j<=width;j++){
   i=base+j-1;c=substr(chunk,j,1)
   if(str){if(esc){esc=0;word=word c}else if(c=="\\")esc=1;else if(c=="\""){str=0;if(depth==1&&word==key&&substr(s,i+1,2)==":[")return i+2}else word=word c;continue}
   if(c=="\""){str=1;word="";continue}
   if(c=="{"||c=="[")depth++
   if(c=="}"||c=="]")depth--
  }
 }return 0
}
function scan(s,start,    base,chunk,width,j,i,c,str,esc,depth,brace,objstart,n){
 delete arr;arrayend=0;str=esc=depth=brace=n=0
 for(base=start;base<=length(s);base+=width){
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
function terminal(o,    x){
 x=o;gsub(/"(outbound|action|type)":"[^"\\]*"/,"",x);gsub(/[{},]/,"",x)
 return x=="" && o~/"outbound":/ && (o!~/"action":/ || o~/"action":"route"/)
}
/^"outbounds":/{
 n=scan($0,index($0,"["));if(n<0)exit 1
 for(i=1;i<=n;i++)if(arr[i]~/"type":"direct"/&&arr[i]~/"tag":"direct"/)direct=1
}
/^"route":/{
 found++;line=$0;rs=field(substr(line,index(line,"{")),"rule_set");offset=index(line,"{")-1
 if(rs){rs+=offset;n=scan(line,rs);if(n<0)exit 1;finish=arrayend;body=""
  for(i=1;i<=n;i++){
   if(arr[i]~/"tag":"panel-cn-ip"/){if(arr[i]!=library())exit 1;continue}
   body=body sprintf("%s%s",body!=""?",":"",arr[i])
  }
  body=body sprintf("%s%s",body!=""?",":"",library());line=substr(line,1,rs) body substr(line,finish)
 }else sub(/^"route":\{/,"\"route\":{\"rule_set\":[" library() "],",line)
 start=field(substr(line,index(line,"{")),"rules")+index(line,"{")-1
 if(start<index(line,"{"))exit 1
 n=scan(line,start);if(n<0)exit 1;finish=arrayend;body="";inserted=0
 fallback="{\"rule_set\":[\"panel-cn-ip\"],\"outbound\":\"direct\"}"
 for(i=1;i<=n;i++){
  if(arr[i]==fallback)continue
  if(!inserted&&terminal(arr[i])){body=body sprintf("%s%s",body!=""?",":"",fallback);inserted=1}
  body=body sprintf("%s%s",body!=""?",":"",arr[i])
 }
 if(!inserted)body=body sprintf("%s%s",body!=""?",":"",fallback)
 print substr(line,1,start) body substr(line,finish);next
}
{print}
END{if(found!=1||!direct)exit 1}
