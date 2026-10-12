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
BEGIN{while((getline line < modes)>0){if(split(line,f,"\t")!=2||f[1]!~/^(auto|manual)$/||f[2]~/["\\\r]/)exit 1;wanted[f[2]]=f[1]}close(modes)}
/^"outbounds":/{
 start=index($0,"[");n=scan($0,start);if(n<0)exit 1;finish=arrayend;body=""
 for(i=1;i<=n;i++){
  obj=arr[i];tag=obj;sub(/^.*"tag":"/,"",tag);sub(/".*$/,"",tag)
  if(tag in wanted && obj~/"type":"(selector|urltest)"/){
   if(tag=="GLOBAL"||tag=="DIRECT")exit 1
   gsub(/,"default":"[^"\\]*"/,"",obj);gsub(/,"url":"[^"\\]*"/,"",obj);gsub(/,"interval":"[^"\\]*"/,"",obj);gsub(/,"tolerance":[0-9]+/,"",obj)
   if(wanted[tag]=="auto"){sub(/"type":"(selector|urltest)"/,"\"type\":\"urltest\"",obj);sub(/}$/,",\"url\":\"https://www.google.com/generate_204\",\"interval\":\"10m\",\"tolerance\":50}",obj)}else sub(/"type":"(selector|urltest)"/,"\"type\":\"selector\"",obj)
   found[tag]=1
  }
  body=body sprintf("%s%s",i>1?",":"",obj)
 }
 if(strict){for(tag in wanted)if(!found[tag])exit 1}
 print substr($0,1,start) body substr($0,finish);seen++;next
}
{print}
END{if(seen!=1)exit 1}
