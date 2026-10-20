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
   # Skip complete quoted tokens using the native regex engine; retain the
   # character-state fallback when a token crosses a chunk boundary.
   if(c=="\""){
    if(match(substr(chunk,j),/^"([^"\\]|\\.)*"/)){j+=RLENGTH-1;continue}
    str=1;continue
   }
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
# Conservative rule eligibility: direct rules + DNS/sniff + mode guards only.
# Reuse the already reviewed canonical JSON scanner.
function direct(o){return o!~/"rules":/ && o~/"outbound":"direct"/ && (o!~/"action":/ || o~/"action":"route"/)}
function guard(o,    x){
 if(o!~/"clash_mode":"(Global|Direct)"/)return 0
 x=o;gsub(/"(clash_mode|outbound|action)":"[^"\\]*"/,"",x);gsub(/[{},]/,"",x)
 return x==""
}
/^"outbounds":/{n=scan($0,index($0,"["));for(i=1;i<=n;i++)if(arr[i]~/"type":"direct"/&&arr[i]~/"tag":"direct"/)valid=1}
/^"route":/{
 found++;start=field(substr($0,index($0,"{")),"rules")+index($0,"{")-1
 if(start<index($0,"{")){parsebad=1;next}
 n=scan($0,start);if(n<0){parsebad=1;next}
 for(i=1;i<=n;i++){
  o=arr[i]
  if(guard(o)||terminal(o)||direct(o)||(o!~/"rules":/ && o~/"action":"(sniff|hijack-dns)"/))continue
  bad=1
 }
}
END{
 if(found!=1||!valid||parsebad)exit 1
 # Report eligibility and the priority warning in one parse for cold status.
 if(report){print bad?"rules":"ready";exit 0}
 if(bad&&!priority)exit 1
}
