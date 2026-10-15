# Small strict JSON reader for recovery metadata on BusyBox, not a shell eval.
# Emits only validated ASCII records. Unknown metadata is parsed, never executed.
function fail(){bad=1;exit 1}
function ws(){while(substr(text,pos,1)~/[ \t\r\n]/&&pos<=length(text))pos++}
function string(    c,out,e){
 if(substr(text,pos++,1)!="\"")fail()
 out=""
 while(pos<=length(text)){
  c=substr(text,pos++,1)
  if(c=="\""){token=out;return}
  if(c=="\\"){
   e=substr(text,pos++,1)
   # Escaped control/Unicode strings are unnecessary for canonical manifests.
   # Reject rather than compare an incompletely decoded security field.
   if(e!="\""&&e!="\\"&&e!="/")fail()
   c=e
  }
  if(c~/[[:cntrl:]]/)fail()
  out=out c
 }fail()
}
function value(path,depth,    c,key,n,start,word){
 if(depth>16||++tokens>2000)fail()
 ws();c=substr(text,pos,1)
 if(c=="{"){
  types[path]="object";pos++;ws()
  if(substr(text,pos,1)=="}"){pos++;return}
  while(1){
   string();key=token
   if(key!~/^[A-Za-z_][A-Za-z0-9_-]*$/||length(key)>64||seen[path ":" key]++)fail()
   ws();if(substr(text,pos++,1)!=":")fail()
   value(path "/" key,depth+1);ws();c=substr(text,pos++,1)
   if(c=="}")return
   if(c!=",")fail()
   ws()
  }
 }else if(c=="["){
  types[path]="array";pos++;ws();n=0
  if(substr(text,pos,1)=="]"){pos++;counts[path]=0;return}
  while(1){
   value(path "/" n++,depth+1);ws();c=substr(text,pos++,1)
   if(c=="]"){counts[path]=n;return}
   if(c!=",")fail()
  }
 }else if(c=="\""){
  string();types[path]="string";vals[path]=token
 }else{
  start=pos
  # Old BusyBox awk and BSD awk disagree on an escaped ] inside a class.
  while(pos<=length(text)){
   c=substr(text,pos,1)
   if(c~/[ \t\r\n]/||c==","||c=="}"||c=="]")break
   pos++
  }
  word=substr(text,start,pos-start)
  if(word=="true"||word=="false"||word=="null"){types[path]="literal";vals[path]=word}
  else if(word~/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/){types[path]="number";vals[path]=word}
  else fail()
 }
}
function sha(s){return length(s)==64&&s!~/[^a-f0-9]/}
function integer(s){return s~/^[1-9][0-9]*$/&&length(s)<=9}
function safe(s,    parts,n,i){
 if(s==""||length(s)>220||s!~/^[A-Za-z0-9_.\/-]+$/||substr(s,1,1)=="/")return 0
 n=split(s,parts,"/");for(i=1;i<=n;i++)if(parts[i]==""||parts[i]=="."||parts[i]=="..")return 0
 return 1
}
{text=text $0 "\n";if(length(text)>16384)fail()}
END{
 if(bad)exit 1
 pos=1;value("",0);ws();if(pos<=length(text)||types[""]!="object")fail()
 if(types["/format"]!="number"||vals["/format"]!="2")fail()
 model=vals["/model"];if(model!=expected_model||(model!="AX5"&&model!="K2P"))fail()
 if(vals["/scope"]!="full-application"&&vals["/scope"]!="full-application-baseline")fail()
 kind=vals["/core_kind"];if(kind!=""&&kind!="meta"&&kind!="singbox")fail()
 if(model=="K2P"&&kind=="meta")fail()
 version=vals["/core_version"];if(version!~/^v?[0-9][A-Za-z0-9._+-]*$/||length(version)>40)fail()
 if(mode=="pointer"||mode=="pointerhash"||mode=="pointerlayout"){
  path=vals["/path"]
  if(!safe(path)||path!~/^baselines\/[A-Za-z0-9_.-]+\/manifest[.]json$/||!sha(vals["/sha256"]))fail()
  if(mode=="pointer")print path
  else if(mode=="pointerhash")print vals["/sha256"]
  else print (vals["/layout"]=="component-directory"?"legacy":"current")
  exit
 }
 if(types["/files"]!="array"||counts["/files"]<3||counts["/files"]>4)fail()
 for(i=0;i<counts["/files"];i++){
  prefix="/files/" i;name=vals[prefix "/name"];path=vals[prefix "/path"]
  if(name!="application.tar.gz"&&name!="core.tar.gz"&&name!="runtime-assets.tar.gz"&&name!="source.tar.gz")fail()
  if(names[name]++)fail()
  if(path=="")path=name
  if(!safe(path)||paths[path]++)fail()
  hash=vals[prefix "/sha256"];size=vals[prefix "/size"]
  limit=(name=="core.tar.gz"?40000000:(name=="source.tar.gz"?20000000:4000000))
  if(!sha(hash)||types[prefix "/size"]!="number"||!integer(size)||size+0>limit)fail()
  records[name]=name "\t" path "\t" size "\t" hash
  if(name=="core.tar.gz"&&hash!=vals["/core_sha256"])fail()
 }
 if(!names["application.tar.gz"]||!names["core.tar.gz"]||!names["runtime-assets.tar.gz"])fail()
 if(mode=="plan"){
  created=vals["/created"];identity=vals["/sha256"]
  if(legacy==1){
   if(identity!=""||created!="")fail()
   created=0
  }else if(!sha(identity)||types["/created"]!="number"||created!~/^[0-9]+$/||length(created)>11)fail()
  for(i=0;i<counts["/files"];i++){
   prefix="/files/" i;total+=vals[prefix "/size"]+0
  }
  tool=vals["/tool_version"];panel=vals["/panel_version"]
  if(tool!~/^[A-Za-z0-9._+-]*$/||length(tool)>40||panel!~/^[A-Za-z0-9._+-]*$/||length(panel)>40)fail()
  printf "{\"model\":\"%s\",\"created\":%s,\"core_kind\":\"%s\",\"core_version\":\"%s\",\"tool_version\":\"%s\",\"panel_version\":\"%s\",\"sha256\":\"%s\",\"size\":%d,\"files\":[",model,created,kind,version,tool,panel,identity,total
  for(i=0;i<counts["/files"];i++){
   prefix="/files/" i;name=vals[prefix "/name"];path=vals[prefix "/path"];if(path=="")path=name
   printf "%s{\"name\":\"%s\",\"path\":\"%s\",\"size\":%s,\"sha256\":\"%s\"}",(i?",":""),name,path,vals[prefix "/size"],vals[prefix "/sha256"]
  }
  print "]}";exit
 }
 # Do not emit partial rows before the entire manifest passes validation.
 print "model\t" model;print "core_kind\t" (kind==""?"unknown":kind);print "core_version\t" version
 print records["application.tar.gz"];print records["core.tar.gz"];print records["runtime-assets.tar.gz"]
}
