-- Isolated filesystem transaction tests. Run with Lua+cjson; never touches live service.
local source=assert(arg[1],'database.lua path required')
local A=dofile(source)
local json=require('cjson')
local base='/tmp/sc-database-transaction-test'
local native_dofile=dofile
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
local count=0
for _,kind in ipairs({'singbox','meta'})do
 for _,case in ipairs({'unchanged','space','fetch','check','start','pending','success'})do
  assert(os.execute('rm -rf '..base..'; mkdir -p '..base..'/persist/configs '..base..'/persist/ruleset '..base..'/persist/cache '..base..'/ram')==0)
  local M={C=base..'/persist',R=base..'/ram'}
  local ext=kind=='meta'and'mrs'or'srs';local path=M.C..'/ruleset/cn.'..ext
  local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
  function M.read(p,max)local f=io.open(p,'rb');if not f then return ''end;local s=f:read(max or'*a');f:close();return s end
  M.write=write;M.quote=quote;M.encode=json.encode
  function M.load()return {route={rule_set={{tag='cn',path=path}}}}end
  function M.save(p,v)write(p,json.encode(v))end
  local calls={};local pid=1;local starts=0
  function M.pid()return pid end
  function M.exec(cmd)
   if cmd:find('df %-k')then return case=='space'and'1'or'4096'end
   local p=assert(io.popen(cmd));local s=p:read('*a');p:close();return s
  end
  function M.run(cmd)
   if cmd:find('database%-source.sh')then
    if case=='fetch'then return false end
    write(M.R..'/domain-candidate.'..ext,case=='unchanged'and string.rep('a',2048)or string.rep('b',2048));write(M.R..'/domain-source','https://example.com/native');return true
   elseif cmd:find('CrashCore',1,true)then return case~='check'
   elseif cmd:find('backup%-config.sh')then return case~='pending'end
   return os.execute(cmd)==0
  end
  local function service(action)
   calls[#calls+1]=action
   if action=='stop'then pid=0 else starts=starts+1;if case=='start'and starts==1 then error('simulated_start_failure')end;pid=1 end
  end
  dofile=function(p)if p:find('mihomo.lua',1,true)then return {build=function()return {['rule-providers']={cn={path=path}}}end}end;return native_dofile(p)end
  write(path,string.rep('a',2048));write(M.C..'/cache/core.env','KIND='..kind..'\n')
  local ok,result=pcall(A.update,M,service)
  if case=='success'or case=='pending'then
   assert(ok,result);assert(M.read(path)==string.rep('b',2048));assert(pid==1);assert(M.read(M.C..'/configs/domain-'..kind..'.json')~='')
   assert(result==(case=='pending'and'configuration_saved_backup_pending'or'database_updated'))
  else
   assert(M.read(path)==string.rep('a',2048),'original changed: '..case);assert(pid==1,'service not restored: '..case)
   if case=='unchanged'then assert(ok and result=='database_unchanged'and #calls==0)else assert(not ok)end
   if case=='space'or case=='fetch'then assert(#calls==0,'unnecessary service interruption')end
  end
  assert(M.read(M.R..'/domain-candidate.'..ext)=='','candidate leaked')
  count=count+1
 end
end
dofile=native_dofile
os.execute('rm -rf '..base)
print('Database transaction checks passed: '..count)
