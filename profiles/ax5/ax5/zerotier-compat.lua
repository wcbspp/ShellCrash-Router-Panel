-- Own only the utun exclusion; preserve the rest of ZeroTier's JSON verbatim.
local M=dofile('/data/ShellCrash/ax5/common.lua')
local fs=require('nixio.fs')
local Z={}
local path='/opt/var/lib/zerotier-one/local.conf'
local service='/opt/etc/init.d/S27zerotier'
local record=M.C..'/configs/zerotier-compat.json'
local pending=M.R..'/zerotier-compat.pending'
local diagnostic=M.R..'/zerotier-compat.error'
local function regular(p,optional)
 local s=fs.lstat(p);assert(not s and optional or s and s.type=='reg','zerotier_unsafe_file')
end
local function read(p,optional)
 regular(p,optional);local s=M.read(p,16385);assert(#s<=16384,'zerotier_config_too_large');return s
end
local function write(p,s)
 regular(p,true);regular(p..'.new',true)
 M.write(p..'.new',s);assert(fs.chmod(p..'.new','600'),'zerotier_permissions_failed')
 assert(os.rename(p..'.new',p),'zerotier_save_failed')
end
local function loadstate(raw)
 if raw==''then return {}end
 local s=M.json.decode(raw)
 assert(type(s)=='table'and s.enabled==true and type(s.added)=='boolean'and type(s.had_list)=='boolean','zerotier_invalid_state')
 return s
end
local function skip(s,i)return s:find('%S',i)or #s+1 end
local function string_end(s,i)
 i=i+1;while i<=#s do local c=s:sub(i,i);if c=='\\'then i=i+2 elseif c=='"'then return i else i=i+1 end end
 error('zerotier_invalid_json')
end
local function value_end(s,i)
 local c=s:sub(i,i);if c=='"'then return string_end(s,i)end
 if c~='{'and c~='['then return (s:find('[,%}%]%s]',i)or #s+1)-1 end
 local depth=0
 while i<=#s do
  c=s:sub(i,i)
  if c=='"'then i=string_end(s,i)
  elseif c=='{'or c=='['then depth=depth+1
  elseif c=='}'or c==']'then depth=depth-1;if depth==0 then return i end end
  i=i+1
 end
 error('zerotier_invalid_json')
end
local function member(s,key)
 local i=skip(s,1);assert(s:sub(i,i)=='{','zerotier_expected_object');i=skip(s,i+1)
 local result
 while s:sub(i,i)~='}'do
  assert(s:sub(i,i)=='"','zerotier_invalid_json');local first=i;local last=string_end(s,i)
  local k=M.json.decode(s:sub(i,last));i=skip(s,last+1);assert(s:sub(i,i)==':','zerotier_invalid_json')
  local a=skip(s,i+1);local b=value_end(s,a)
  if k==key then assert(not result,'zerotier_duplicate_key');result={first=first,a=a,b=b}end
  i=skip(s,b+1);if s:sub(i,i)==','then i=skip(s,i+1)else assert(s:sub(i,i)=='}','zerotier_invalid_json')end
 end
 return result,i
end
local function replace(s,key,value)
 local m,close=member(s,key)
 if m then
  if value then return s:sub(1,m.a-1)..value..s:sub(m.b+1)end
  local after=skip(s,m.b+1)
  if s:sub(after,after)==','then return s:sub(1,m.first-1)..s:sub(after+1)end
  local before=m.first-1;while s:sub(before,before):match('%s')do before=before-1 end
  if s:sub(before,before)==','then return s:sub(1,before-1)..s:sub(m.b+1)end
  return s:sub(1,m.first-1)..s:sub(m.b+1)
 end
 if not value then return s end
 local empty=not s:sub(1,close-1):find(':',1,true)
 return s:sub(1,close-1)..(empty and''or',')..M.json.encode(key)..':'..value..s:sub(close)
end
function Z.patch(raw,enable,owned)
 local c=M.json.decode(raw);assert(type(c)=='table','zerotier_invalid_json')
 local sm=member(raw,'settings');local settings=sm and raw:sub(sm.a,sm.b)or'{}'
 assert(settings:match('^%s*{'),'zerotier_invalid_settings')
 local lm=member(settings,'interfacePrefixBlacklist');local list=lm and M.json.decode(settings:sub(lm.a,lm.b))or{}
 assert(not lm or settings:sub(lm.a,lm.a)=='[','zerotier_invalid_exclusions')
 assert(type(list)=='table'and #list<=64,'zerotier_invalid_exclusions')
 local found=false;for _,v in ipairs(list)do assert(type(v)=='string'and #v<=128,'zerotier_invalid_exclusions');if v=='utun'then found=true end end
 local changed=false;local added=owned and owned.added or false
 if enable and not found then assert(#list<64,'zerotier_too_many_exclusions');list[#list+1]='utun';added=true;changed=true
 elseif not enable and added and found then
  local keep={};for _,v in ipairs(list)do if v~='utun'then keep[#keep+1]=v end end;list=keep;changed=true
 end
 if not changed then return raw,added,not not lm end
 local values={};for _,v in ipairs(list)do values[#values+1]=M.json.encode(v)end
 local encoded='['..table.concat(values,',')..']'
 if not enable and #list==0 and owned and not owned.had_list then encoded=nil end
 local nextsettings=replace(settings,'interfacePrefixBlacklist',encoded)
 local result=replace(raw,'settings',nextsettings)
 M.json.decode(result)
 return result,added,not not lm
end
function Z.status()
 local ok,raw=pcall(read,path,false)
 local stateok,state=pcall(function()return loadstate(read(record,true))end)
 if not stateok then state={}end
 local out={available=ok and stateok and M.read(service,2)~='',enabled=state.enabled==true,protected=false,managed=state.added==true}
 if ok then local good,c=pcall(M.json.decode,raw);if good and type(c)=='table'and type(c.settings)=='table'and type(c.settings.interfacePrefixBlacklist)=='table'then for _,v in ipairs(c.settings.interfacePrefixBlacklist)do if v=='utun'then out.protected=true end end end end
 out.error=not stateok and'invalid_state'or M.read(diagnostic,128):gsub('%s+$','');out.pending=M.read(pending)~=''
 return out
end
local function restart()
 assert(M.run(service..' restart >/dev/null 2>&1'),'zerotier_restart_failed')
 assert(M.exec('pidof zerotier-one 2>/dev/null'):match('%d'),'zerotier_not_running')
end
function Z.set(enable,defer)
 assert(type(enable)=='boolean','invalid_zerotier_setting')
 assert(M.lock('zerotier-compat.lock',60),'zerotier_compat_busy')
 local old,oldstate,new,changed,wasrunning
 local ok,result=pcall(function()
  M.write(M.R..'/zerotier-compat.lock/owner',tostring(require('nixio').getpid()))
  old=read(path,false);oldstate=read(record,true)
  assert(M.read(service,2)~='','zerotier_service_missing')
  local state=loadstate(oldstate)
  local added,had;new,added,had=Z.patch(old,enable,state)
  if not enable and state.added and old==read(M.C..'/configs/zerotier-compat.applied',true)then
   local original=read(M.C..'/configs/zerotier-compat.before',false);M.json.decode(original);new=original
  end
  wasrunning=M.exec('pidof zerotier-one 2>/dev/null'):match('%d')~=nil
  changed=new~=old
  if changed then
   if enable then write(M.C..'/configs/zerotier-compat.before',old)end
   assert(read(path,false)==old,'zerotier_config_changed')
   write(path,new)
   if enable then write(M.C..'/configs/zerotier-compat.applied',new)end
  end
  if state.enabled then had=state.had_list end
  if enable then write(record,M.json.encode({enabled=true,added=added,had_list=had}))else os.remove(record);os.remove(pending)end
  assert(M.run('sync'),'zerotier_sync_failed')
  if changed and wasrunning then
   if defer then M.write(pending,'1\n')else restart();os.remove(pending)end
  end
  os.remove(diagnostic);return changed
 end)
 if not ok then
  if changed and old and M.read(path)==new then pcall(write,path,old);if wasrunning then pcall(restart)end end
  if oldstate then if oldstate==''then os.remove(record)else pcall(write,record,oldstate)end end
  M.write(diagnostic,'apply_failed\n')
 end
 os.remove(M.R..'/zerotier-compat.lock/owner');os.remove(M.R..'/zerotier-compat.lock');os.remove(M.R..'/zerotier-compat.lock.time')
 if not ok then error(result,0)end
 return result
end
function Z.enforce()
 local stateok,state=pcall(function()return loadstate(read(record,true))end)
 if not stateok then M.write(diagnostic,'invalid_state\n');return end
 if state.enabled~=true or Z.status().protected then return end
 local ok=pcall(Z.set,true,true);if not ok then M.write(diagnostic,'enforce_failed\n')end
end
function Z.finish()
 if M.read(pending)==''then return end
 local okstate,state=pcall(function()return loadstate(read(record,true))end)
 if not okstate or state.enabled~=true or not M.exec('pidof zerotier-one 2>/dev/null'):match('%d')then os.remove(pending);return end
 if not M.lock('zerotier-compat.lock',60)then return end
 local ok=pcall(function()
  M.write(M.R..'/zerotier-compat.lock/owner',tostring(require('nixio').getpid()))
  restart()
 end)
 if ok then os.remove(pending);os.remove(diagnostic)else M.write(diagnostic,'restart_pending\n')end
 os.remove(M.R..'/zerotier-compat.lock/owner');os.remove(M.R..'/zerotier-compat.lock');os.remove(M.R..'/zerotier-compat.lock.time')
end
if arg and arg[1]=='enforce'then Z.enforce()elseif arg and arg[1]=='finish'then Z.finish()end
return Z
