-- Bounded tar/gzip validation. Never extracts or executes archive members.
local component,path,expected=arg[1],arg[2],arg[3]
local model=arg[4] or 'AX5'
assert(model=='AX5' or model=='K2P','unknown model')
assert(component=='application' or component=='runtime-assets' or component=='core','unknown component')
assert(type(path)=='string' and #path<300 and not path:find('[%c]'),'invalid archive path')
assert(type(expected)=='string' and #expected==64 and not expected:find('[^a-f0-9]'),'invalid core hash')
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
-- Parse the bounded stream before CRC verification: gzip -t alone has no
-- expansion bound and Padavan has no timeout applet.
local stream=assert(io.popen('gzip -dc '..quote(path),'r'))
local total,entries,unpacked=0,0,0
local max_total=component=='core' and 80000000 or 16000000
local function read(n)
 local data=stream:read(n);if not data then return nil end
 total=total+#data;assert(total<=max_total,'unpacked archive exceeds limit')
 return data
end
local function octal(s)
 s=s:gsub('%z.*$',''):match('^%s*(.-)%s*$')
 assert(s:match('^[0-7]+$'),'invalid tar number');return assert(tonumber(s,8))
end
local roots={configs=true,ui=true,ax5=true,ruleset=true,cache=true,['ShellCrash-tool']=true,['backup.info']=true,['RESTORE.txt']=true,['使用说明.txt']=true}
if model=='K2P' then
 roots={configs=true,ui=true,padavan=true,starts=true,libs=true,tools=true,menus=true,task=true,jsons=true,yamls=true,ruleset=true,
 ['start.sh']=true,['menu.sh']=true,['init.sh']=true,version=true,['task_en.list']=true,['task.list']=true,
 ['singbox_providers.list']=true,['servers.list']=true,['clash_providers.list']=true,['fallback_filter.list']=true,
 ['fake_ip_filter.list']=true,['cn_ipv6.txt']=true,['backup.info']=true,['RESTORE.txt']=true,['使用说明.txt']=true}
end
local protected={['webdav.auth']=true,['webdav.user']=true,['mirror-id']=true,mirror_key=true,mirror_known_hosts=true,['remote.verified']=true}
local seen,captured,used_as_parent={},{},{}
local limits={['configs/config.json']=1500000,['cache/core.env']=4096,['cache/core.sha256']=128,['configs/enabled']=16,['backup.info']=4096}
limits['configs/core-installed.info']=4096;limits['jsons/config.json']=1500000
local ended=false
local function kv(raw)
 local result={}
 for line in raw:gmatch('[^\r\n]+')do
  local k,v=line:match('^([%w_]+)=(.*)$')
  if k then assert(result[k]==nil,'duplicate metadata key');result[k]=v end
 end
 return result
end
local metadata={}
local resource_bytes,resource_members=0,0
local resource_files={}
local ok,err=pcall(function()
 while true do
  local header=read(512);if not header then break end
  assert(#header==512,'truncated tar header')
  if header==string.rep('\0',512)then ended=true
  else
   assert(not ended,'nonzero data after tar end')
   entries=entries+1;assert(entries<=8000,'too many archive entries')
   local check=octal(header:sub(149,156));local sum=0
   for n=1,512 do sum=sum+((n>=149 and n<=156)and 32 or header:byte(n))end
   assert(sum==check,'tar checksum failed')
   local name=header:sub(1,100):gsub('%z.*$','');local prefix=header:sub(346,500):gsub('%z.*$','')
   if prefix~=''then name=prefix..'/'..name end
   while name:sub(1,2)=='./'do name=name:sub(3)end
   name=name:gsub('/+$','')
   local kind=header:sub(157,157);local directory=kind=='5';local regular=kind=='0'or kind=='\0'
   assert(directory or regular,'links and special tar entries are forbidden')
   local size=octal(header:sub(125,136));assert(size<=80000000,'member exceeds limit')
   local mode=octal(header:sub(101,108));assert(math.floor(mode/1024)%4==0,'special permissions forbidden')
   if name==''or name=='.'then assert(directory and size==0,'invalid root entry')
   else
    assert(#name<=300 and name:sub(1,1)~='/'and not name:find('[%c\\]')and not name:find('//',1,true),'invalid archive path')
    for part in name:gmatch('[^/]+')do assert(part~='.'and part~='..','archive traversal')end
    assert(not seen[name],'duplicate archive path')
    local parent=''
    for part in name:gmatch('[^/]+')do
     if parent~=''then assert(seen[parent]~='file','file used as parent directory');used_as_parent[parent]=true end
     parent=parent==''and part or parent..'/'..part
    end
    assert(not regular or not used_as_parent[name],'file shadows directory')
    seen[name]=directory and 'directory' or 'file'
    if component=='application'then
     assert(roots[name:match('^[^/]+')],'unexpected application root')
     if name:sub(1,8)=='configs/'then assert(not protected[name:match('[^/]+$')],'credentials inside portable backup')end
    elseif component=='core'then assert(name=='CrashCore'and regular,'core must contain only CrashCore')
    else
     local allowed=name=='ShellCrash-dashboard'or name:sub(1,21)=='ShellCrash-dashboard/'or name=='ShellCrash/runtime-backup.info'
     if model=='K2P'then allowed=allowed or name=='sc-admin/runtime-backup.info'or name=='ShellCrash/ruleset'or name:sub(1,#'ShellCrash/ruleset/')=='ShellCrash/ruleset/' end
     assert(allowed,'unexpected runtime root')
    end
   end
   assert(not directory or size==0,'directory contains data')
   if regular then unpacked=unpacked+size end
   if component=='application'and model=='AX5'and arg[6]=='resources'and regular and(name:match('^ruleset/')or name=='configs/cn_ip.txt'or name=='configs/policy.tsv')then
    resource_bytes=resource_bytes+size;resource_members=resource_members+1
    assert(size<=2000000 and resource_bytes<=math.min(4000000,tonumber(os.getenv("SC_RECOVERY_RESOURCE_MAX"))or 4000000),'preflight resources exceed capture budget')
    limits[name]=2000000;resource_files[name]=true
   end
   if limits[name]then assert(size<=limits[name],'metadata file exceeds limit')end
   local remaining=size;local parts={};local first=true
   while remaining>0 do
    local block=assert(read(math.min(65536,remaining)),'truncated member');assert(#block>0,'empty member block');remaining=remaining-#block
    if first and component=='core'then assert(#block>=20 and block:sub(1,6)=='\127ELF\1\1'and block:byte(19)==(model=='AX5'and 40 or 8) and block:byte(20)==0,'wrong core ELF architecture')end
    first=false
    if limits[name]then parts[#parts+1]=block end
   end
   if limits[name]then captured[name]=table.concat(parts)end
   local padding=(512-size%512)%512;if padding>0 then local data=assert(read(padding),'missing member padding');assert(#data==padding,'truncated padding')end
  end
 end
 assert(ended,'missing tar end')
 if component=='core'then assert(seen.CrashCore and entries==1,'invalid core member count')end
 if component=='application'and model=='AX5'then
  for _,name in ipairs({'backup.info','configs/config.json','configs/enabled','cache/core.env','ax5/api.lua','ax5/prepare.sh','ax5/shellcrash.init','ShellCrash-tool/configs/ShellCrash.cfg'})do assert(seen[name]=='file','missing '..name)end
  local info=captured['backup.info'];assert(info:match('^model=AX5[\r\n]')or info:match('[\r\n]model=AX5[\r\n]'),'wrong internal model')
  local env=captured['cache/core.env'];local value=env:match('^HASH=([^\r\n]+)')or env:match('[\r\n]HASH=([^\r\n]+)');assert(value,'missing core hash')
  value=value:gsub("^['\"]",''):gsub("['\"]$",'');assert(value==expected,'core environment mismatch')
  if captured['cache/core.sha256']then assert(captured['cache/core.sha256']:gsub('%s+$','')==expected,'core record mismatch')end
  assert(captured['configs/enabled']:match('^[01]%s*$'),'invalid startup state')
  local config=require('cjson').decode(captured['configs/config.json']);assert(type(config)=='table','invalid configuration')
  metadata.enabled=tonumber(captured['configs/enabled']);metadata.autostart=seen['ShellCrash-tool/.dis_startup']and 0 or 1
 end
 if component=='application'and model=='K2P'then
  for _,name in ipairs({'backup.info','start.sh','menu.sh','menus/bot_tg_service.sh','starts/panel_boot.sh','configs/ShellCrash.cfg','configs/core-installed.info','jsons/config.json'})do assert(seen[name]=='file','missing '..name)end
  local info=kv(captured['backup.info']);local core=kv(captured['configs/core-installed.info'])
  assert(info.model=='K2P','wrong internal model')
  assert(core.arch=='mipsle-softfloat'and core.sha256==expected,'core record mismatch')
  assert(core.version and core.version:match('^[0-9][0-9.]+$')and #core.version<=30,'invalid core version')
  assert((info.enabled=='0'or info.enabled=='1')and(info.autostart=='0'or info.autostart=='1'),'missing startup state')
  assert(info.traffic_mode=='rule'or info.traffic_mode=='direct'or info.traffic_mode=='global','invalid traffic mode')
  local config=require('cjson').decode(captured['jsons/config.json'])
  assert(type(config)=='table'and type(config.outbounds)=='table'and #config.outbounds>0,'invalid configuration')
  metadata={enabled=tonumber(info.enabled),autostart=tonumber(info.autostart),traffic_mode=info.traffic_mode,core_version=core.version}
 end
end)
stream:close()
assert(ok,err)
assert(os.execute('gzip -t '..quote(path)..' 2>/dev/null')==0,'gzip CRC check failed')
metadata.component=component;metadata.members=entries;metadata.unpacked_size=unpacked;metadata.model=model
metadata.resource_size=resource_bytes;metadata.resource_members=resource_members
-- Optional fixed destination supplied by the trusted preflight supervisor.
-- Only the already validated configuration is written; no archive paths are used.
if arg[5]then
 assert(component=='application','configuration export requires application archive')
 assert(arg[5]:match('^/tmp/sc%-preflight%-%x%x%x%x%x%x%x%x/config%.original%.json$'),'invalid configuration destination')
 local base=arg[5]:match('^(.*)/config%.original%.json$')
 for name in pairs(resource_files)do
  local target=base..'/app/'..name
  assert(os.execute('mkdir -p '..quote(target:match('^(.*)/[^/]+$')))==0,'cannot create resource directory')
  local out=assert(io.open(target,'wb'));assert(out:write(captured[name]));assert(out:close())
 end
 local f=assert(io.open(arg[5],'wb'));assert(f:write(captured[model=='K2P'and'jsons/config.json'or'configs/config.json']));assert(f:close())
end
print(require('cjson').encode(metadata))
