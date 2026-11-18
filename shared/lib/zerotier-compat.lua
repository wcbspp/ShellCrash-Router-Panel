-- Own only the utun exclusion; preserve the rest of ZeroTier's JSON verbatim.
local M,adapter=...
assert(type(M)=='table'and type(adapter)=='table','missing_zerotier_adapter')
local fs=require('nixio.fs')
M.json=M.json or require('cjson')
M.read=M.read or function(p,max)local f=io.open(p,'rb');if not f then return''end;local s=f:read(max or'*a')or'';f:close();return s end
M.write=M.write or function(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));assert(f:close())end
M.quote=M.quote or function(s)return "'"..s:gsub("'","'\\''").."'"end
M.run=M.run or function(s)return os.execute(s)==0 end
M.exec=M.exec or function(s)local p=assert(io.popen(s));local out=p:read('*a');p:close();return out end
M.lock=M.lock or function(name,ttl)
 local p=M.R..'/'..name
 if M.run('mkdir '..M.quote(p)..' 2>/dev/null')then M.write(p..'.time',tostring(os.time()));return true end
 local owner=M.read(p..'/owner'):match('^(%d+)%s*$')
 if owner and M.run('kill -0 '..owner..' 2>/dev/null')then return false end
 local stamp=tonumber(M.read(p..'.time'));local stat=fs.stat(p);stamp=stamp or(stat and stat.mtime)
 if stamp and os.time()-stamp>ttl then
  os.remove(p..'/owner');if M.run('rmdir '..M.quote(p)..' 2>/dev/null')then os.remove(p..'.time');return M.lock(name,ttl)end
 end
 return false
end
local Z={}
local function safe_path(path)
 return type(path)=='string' and #path<512 and path:match('^/[A-Za-z0-9_./-]+$')
  and not path:match('/%.%.?/') and not path:match('/%.%.?$')
end
local function persistent_home(path)
 local dir=path
 while dir~='' do
  local st=fs.stat(dir)
  if not st or st.type~='dir' or st.uid~=0 or not st.modestr or st.modestr:sub(5,5)=='w' or st.modestr:sub(8,8)=='w' then return false end
  dir=dir:match('^(.*)/[^/]+$') or ''
 end
 if adapter.storage_root and path:sub(1,#adapter.storage_root+1)==adapter.storage_root..'/' then return true end
 local mount,kind='',nil
 for dir,fs_type in M.read('/proc/mounts',65536):gmatch('%S+ (%S+) (%S+)[^\n]*') do
  if (dir=='/' or path==dir or path:sub(1,#dir+1)==dir..'/') and #dir>#mount then mount,kind=dir,fs_type end
 end
 local local_disk={ext2=true,ext3=true,ext4=true,ubifs=true,jffs2=true,f2fs=true,xfs=true,btrfs=true}
 return local_disk[kind]==true
end
local function configured_home()
 local declared=adapter.configured_home and adapter.configured_home() or (not adapter.configured_home and adapter.home)
 if not safe_path(declared) then return nil end
 local resolved=fs.realpath(declared)
 if not safe_path(resolved) then return nil end
 if resolved~=adapter.home and not persistent_home(resolved) then return nil end
 return resolved
end
local home=adapter.binary and configured_home() or (not adapter.binary and adapter.home)
local namespace=''
local namespace_ok=true
if adapter.binary and home and home~=adapter.home then
 local sum=M.exec('printf %s '..M.quote(home)..' | openssl dgst -sha256 2>/dev/null'):match('(%x+)%s*$')
 namespace_ok=sum~=nil and #sum==64
 if namespace_ok then namespace='-'..sum end
end
local path=home and home..'/local.conf' or assert(adapter.path)
Z.home=home or adapter.home
local prefix=assert(adapter.prefix)
assert(prefix:match('^[%w_-]+$')and #prefix<=32,'invalid_tun_prefix')
local backup=M.C..'/configs/zerotier-compat'..namespace
local record=backup..'.json'
local pending=M.R..'/zerotier-compat'..namespace..'.pending'
local diagnostic=M.R..'/zerotier-compat'..namespace..'.error'
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
 assert(type(s)=='table'and (s.home==nil and namespace=='' or s.home==home) and s.enabled==true and type(s.added)=='boolean'and type(s.had_list)=='boolean'and(s.prefix==nil or s.prefix==prefix),'zerotier_invalid_state')
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
 local found=false;for _,v in ipairs(list)do assert(type(v)=='string'and #v<=128,'zerotier_invalid_exclusions');if v==prefix then found=true end end
 local changed=false;local added=owned and owned.added or false
 if enable and not found then assert(#list<64,'zerotier_too_many_exclusions');list[#list+1]=prefix;added=true;changed=true
 elseif not enable and added and found then
  local keep={};for _,v in ipairs(list)do if v~=prefix then keep[#keep+1]=v end end;list=keep;changed=true
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
local function target()
 if not adapter.available() then return false end
 if not adapter.binary then return true end
 if not namespace_ok or not home or configured_home()~=home then return false end
 local pids=M.exec('pidof zerotier-one 2>/dev/null')
 if not pids:match('%S') then return true end
 local pid=pids:match('^%s*(%d+)%s*$')
 if not pid or fs.readlink('/proc/'..pid..'/exe')~=adapter.binary then return false end
 local args={}
 for v in M.read('/proc/'..pid..'/cmdline',4096):gmatch('([^%z]+)%z') do args[#args+1]=v end
 if args[1]~=adapter.binary or not (#args==2 or (#args==3 and args[2]=='-d')) then return false end
 local active=args[#args]
 if not safe_path(active) or fs.realpath(active)~=home then return false end
 return true,active
end
function Z.status()
 local matched=target()
 local ok,raw=false,nil
 if matched then ok,raw=pcall(read,path,adapter.allow_missing==true) end
 local stateok,state=pcall(function()return loadstate(read(record,true))end)
 if not matched or not stateok then state={}end
 local out={available=ok and stateok,config_path=matched and path or nil,enabled=state.enabled==true,protected=false,managed=state.added==true}
 if ok then local good,c=pcall(M.json.decode,raw);if good and type(c)=='table'and type(c.settings)=='table'and type(c.settings.interfacePrefixBlacklist)=='table'then for _,v in ipairs(c.settings.interfacePrefixBlacklist)do if v==prefix then out.protected=true end end end end
 out.policy='exclude_tun_interfaces';out.tun_prefix=prefix
 out.error=not stateok and'invalid_state'or M.read(diagnostic,128):gsub('%s+$','');out.pending=M.read(pending)~=''
 return out
end
local function restart()
 local verified,active=target()
 assert(verified and (active or not adapter.binary),'zerotier_target_unverified')
 assert(adapter.restart(active),'zerotier_restart_failed')
 assert(M.exec('pidof zerotier-one 2>/dev/null'):match('%d'),'zerotier_not_running')
end
function Z.set(enable,defer)
 assert(type(enable)=='boolean','invalid_zerotier_setting')
 assert(target(),'zerotier_target_unverified')
 assert(M.lock('zerotier-compat.lock',60),'zerotier_compat_busy')
 local old,oldstate,new,changed,wasrunning
 local function persist()if adapter.persist then assert(adapter.persist(),'zerotier_persist_failed')end;assert(M.run('sync'),'zerotier_sync_failed')end
 local ok,result=pcall(function()
  M.write(M.R..'/zerotier-compat.lock/owner',tostring(require('nixio').getpid()))
  assert(target(),'zerotier_target_unverified')
  old=read(path,adapter.allow_missing==true);oldstate=read(record,true)
  local state=loadstate(oldstate)
  local missing=not fs.lstat(path)
  local restoring=enable and state.enabled and missing and adapter.allow_missing
  local base=restoring and read(backup..'.applied',false)or(missing and'{}'or old)
  local added,had;new,added,had=Z.patch(base,enable,state)
  if not enable and missing then new=''end
  if not enable and state.added and old==read(backup..'.applied',true)then
   local original=read(backup..'.before',false);if original~=''then M.json.decode(original)end;new=original
  end
  wasrunning=M.exec('pidof zerotier-one 2>/dev/null'):match('%d')~=nil
  changed=new~=old
  if changed then
   if enable and not state.enabled then write(backup..'.before',old)end
   assert(read(path,adapter.allow_missing==true)==old,'zerotier_config_changed')
   if new==''then assert(not fs.lstat(path)or os.remove(path),'zerotier_remove_failed')else write(path,new)end
  end
  if state.enabled then had=state.had_list end
  if enable then write(backup..'.applied',new);write(record,M.json.encode({enabled=true,added=added,had_list=had,prefix=prefix,home=home}))else os.remove(record);os.remove(pending)end
  persist()
  if changed and wasrunning then
   if defer then M.write(pending,'1\n')else restart();os.remove(pending)end
  end
  os.remove(diagnostic);return changed
 end)
 if not ok then
  if changed and old and M.read(path)==new then if old==''then os.remove(path)else pcall(write,path,old)end;if wasrunning then pcall(restart)end end
  if oldstate then if oldstate==''then os.remove(record)else pcall(write,record,oldstate)end end
  if oldstate then pcall(persist)end;M.write(diagnostic,'apply_failed\n')
 end
 os.remove(M.R..'/zerotier-compat.lock/owner');os.remove(M.R..'/zerotier-compat.lock');os.remove(M.R..'/zerotier-compat.lock.time')
 if not ok then error(result,0)end
 return result
end
function Z.enforce()
 local stateok,state=pcall(function()return loadstate(read(record,true))end)
 if not stateok then M.write(diagnostic,'invalid_state\n');return end
 if not target() or state.enabled~=true or Z.status().protected then return end
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
return Z
