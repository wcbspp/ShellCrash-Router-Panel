-- Bounded tar/gzip validation. Never extracts or executes archive members.
local component,path,expected=arg[1],arg[2],arg[3]
assert(component=='application' or component=='runtime-assets' or component=='core','unknown component')
assert(type(path)=='string' and #path<300 and not path:find('[%c]'),'invalid archive path')
assert(type(expected)=='string' and #expected==64 and not expected:find('[^a-f0-9]'),'invalid core hash')
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
assert(os.execute('timeout -t 20 gzip -t '..quote(path))==0,'gzip CRC check failed')
local stream=assert(io.popen('gzip -dc '..quote(path),'r'))
local total,entries=0,0
local function read(n)
 local data=stream:read(n);if not data then return nil end
 total=total+#data;assert(total<=160000000,'unpacked archive exceeds limit')
 return data
end
local function octal(s)
 s=s:gsub('%z.*$',''):match('^%s*(.-)%s*$')
 assert(s:match('^[0-7]+$'),'invalid tar number');return assert(tonumber(s,8))
end
local roots={configs=true,ui=true,ax5=true,ruleset=true,cache=true,['ShellCrash-tool']=true,['backup.info']=true,['RESTORE.txt']=true,['使用说明.txt']=true}
local protected={['webdav.auth']=true,['webdav.user']=true,['mirror-id']=true,mirror_key=true,mirror_known_hosts=true,['remote.verified']=true}
local seen,captured={},{}
local limits={['configs/config.json']=1500000,['cache/core.env']=4096,['cache/core.sha256']=128,['configs/enabled']=16,['backup.info']=4096}
local ended=false
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
    assert(not seen[name],'duplicate archive path');seen[name]=true
    if component=='application'then
     assert(roots[name:match('^[^/]+')],'unexpected application root')
     if name:sub(1,8)=='configs/'then assert(not protected[name:match('[^/]+$')],'credentials inside portable backup')end
    elseif component=='core'then assert(name=='CrashCore'and regular,'core must contain only CrashCore')
    else assert(name=='ShellCrash-dashboard'or name:sub(1,21)=='ShellCrash-dashboard/'or name=='ShellCrash/runtime-backup.info','unexpected runtime root')end
   end
   assert(not directory or size==0,'directory contains data')
   if limits[name]then assert(size<=limits[name],'metadata file exceeds limit')end
   local remaining=size;local parts={};local first=true
   while remaining>0 do
    local block=assert(read(math.min(65536,remaining)),'truncated member');assert(#block>0,'empty member block');remaining=remaining-#block
    if first and component=='core'then assert(#block>=20 and block:sub(1,6)=='\127ELF\1\1'and block:byte(19)==40 and block:byte(20)==0,'wrong core ELF architecture')end
    first=false
    if limits[name]then parts[#parts+1]=block end
   end
   if limits[name]then captured[name]=table.concat(parts)end
   local padding=(512-size%512)%512;if padding>0 then local data=assert(read(padding),'missing member padding');assert(#data==padding,'truncated padding')end
  end
 end
 assert(ended,'missing tar end')
 if component=='core'then assert(seen.CrashCore and entries==1,'invalid core member count')end
 if component=='application'then
  for _,name in ipairs({'backup.info','configs/config.json','configs/enabled','cache/core.env','ax5/api.lua','ax5/prepare.sh','ax5/shellcrash.init','ShellCrash-tool/configs/ShellCrash.cfg'})do assert(seen[name],'missing '..name)end
  local info=captured['backup.info'];assert(info:match('^model=AX5[\r\n]')or info:match('[\r\n]model=AX5[\r\n]'),'wrong internal model')
  local env=captured['cache/core.env'];local value=env:match('^HASH=([^\r\n]+)')or env:match('[\r\n]HASH=([^\r\n]+)');assert(value,'missing core hash')
  value=value:gsub("^['\"]",''):gsub("['\"]$",'');assert(value==expected,'core environment mismatch')
  if captured['cache/core.sha256']then assert(captured['cache/core.sha256']:gsub('%s+$','')==expected,'core record mismatch')end
  assert(captured['configs/enabled']:match('^[01]%s*$'),'invalid startup state')
  local config=require('cjson').decode(captured['configs/config.json']);assert(type(config)=='table','invalid configuration')
 end
end)
stream:close()
assert(ok,err)
print('archive_valid '..component..' '..entries..' '..total)
