BEGIN{wanted=ENVIRON["NODE_PING_KEY"];catalog=ENVIRON["NODE_PING_CATALOG"]=="1";for(b=1;b<256;b++)ord[sprintf("%c",b)]=b}
function key(t,    i,h){h=0;for(i=1;i<=length(t);i++)h=(h*131+ord[substr(t,i,1)])%2147483647;return sprintf("%.0f",h)}
# Read only the canonical K2P outbounds line; retain no credentials or node table.
function bad(){error=1;exit 1}
function charAt(i,    base){if(i<cacheStart||i>=cacheStart+cacheSize){base=int((i-1)/128)*128+1;cache=substr(s,base,128);cacheStart=base;cacheSize=length(cache)}return substr(cache,i-cacheStart+1,1)}
function ws(){while(charAt(p)~/[ \t\r\n]/&&p<=size)p++}
function hex4(    i,c,n){n=0;for(i=0;i<4;i++){c=index("0123456789abcdef",tolower(charAt(p+i)))-1;if(c<0)bad();n=n*16+c}p+=4;return n}
function utf(n){if(n<128)return sprintf("%c",n);if(n<2048)return sprintf("%c%c",192+int(n/64),128+n%64);if(n<65536)return sprintf("%c%c%c",224+int(n/4096),128+int(n/64)%64,128+n%64);return sprintf("%c%c%c%c",240+int(n/262144),128+int(n/4096)%64,128+int(n/64)%64,128+n%64)}
function str(    c,e,n,m,out,part){
 part=substr(s,p)
 if(match(part,/^"[^"\\[:cntrl:]]*"/)){token=substr(part,2,RLENGTH-2);if(length(token)>16384)bad();p+=RLENGTH;return}
 if(charAt(p++)!="\"")bad();out=""
 while(p<=size){c=charAt(p++);if(c=="\""){token=out;return}if(c~/[[:cntrl:]]/)bad()
  if(c=="\\"){e=charAt(p++);if(e=="u"){n=hex4();if(n>=55296&&n<=56319){if(substr(s,p,2)!="\\u")bad();p+=2;m=hex4();if(m<56320||m>57343)bad();n=65536+(n-55296)*1024+m-56320}else if(n>=56320&&n<=57343)bad();c=utf(n)}
   else if(e=="\""||e=="\\"||e=="/")c=e;else if(e~/^[bfnrt]$/)c="\001";else bad()}
  out=out c;if(length(out)>16384)bad()
 }bad()
}
function val(depth,    c,key,start,word,field){
 if(depth>24||++tokens>100000)bad();ws();c=charAt(p)
 if(c=="{"){p++;ws();if(charAt(p)=="}"){p++;return}while(1){str();key=token;ws();if(charAt(p++)!=":")bad();ws();field=(depth==1&&(key=="tag"||key=="server"||key=="detour"));if(field){if(seen[key]++)bad();if(charAt(p)!="\"")bad();str();v[key]=token}else val(depth+1);ws();c=charAt(p++);if(c=="}")return;if(c!=",")bad();ws()}}
 else if(c=="["){p++;ws();if(charAt(p)=="]"){p++;return}while(1){val(depth+1);ws();c=charAt(p++);if(c=="]")return;if(c!=",")bad()}}
 else if(c=="\"")str();else{start=p;while(charAt(p)~/[A-Za-z0-9+.eE-]/&&p<=size)p++;word=substr(s,start,p-start);if(word!="true"&&word!="false"&&word!="null"&&word!~/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/)bad()}
}
/^"outbounds":/{
 if(foundline++||length($0)>262144)bad();s=substr($0,index($0,"["));size=length(s);cacheStart=0;cacheSize=0;p=2;ws()
 while(charAt(p)!="]"){
  delete v;delete seen;start=p;if(charAt(p)!="{")bad();val(1);if(p-start>16384)bad()
  if(catalog&&("tag" in v)){candidate=v["server"];if(candidate==""||v["detour"]!=""||length(candidate)>253||candidate!~/^[A-Za-z0-9][A-Za-z0-9.-]*$/||candidate~/\.\.|\.$/)candidate="-";print key(v["tag"]) "\t" candidate}
  else if(("tag" in v)&&key(v["tag"])==wanted){matches++;host=v["server"];detour=v["detour"]}
  ws();c=charAt(p++);if(c=="]")break;if(c!=",")bad();ws()
 }
}
END{if(catalog){if(error||foundline!=1)exit 1;exit 0}if(error||foundline!=1||matches!=1||host==""||detour!=""||length(host)>253||host!~/^[A-Za-z0-9][A-Za-z0-9.-]*$/||host~/\.\.|\.$/)exit 1;print host}
