-- Exercise the actual publication function with isolated in-memory files/services.
local json=require('cjson');local f=assert(io.open(arg[1]or'/data/ShellCrash/ax5/job.lua'));local source=f:read('*a');f:close()
local first=assert(source:find('local function checked_save(cfg)',1,true));local last=assert(source:find('local function fetched',first,true));local fn=source:sub(first,last-1)..'return checked_save'
for _,failure in ipairs({'none','check','start'})do
 local files={['C/configs/config.json']='OLD',['C/configs/policy.tsv']='OLD POLICY'}
 local events={};local started=false
 local M={C='C',R='R',json=json,quote=function(s)return s end,encode=json.encode}
 M.read=function(p)return files[p]or'' end
 M.write=function(p,s)files[p]=s end
 M.save=function(p,c)files[p]=json.encode(c)end
 M.pid=function()return 1 end;M.state=function()return {core_kind='meta'}end;M.memory=function()return {MemAvailable=50000}end
 M.run=function(cmd)if cmd:find(' -t ',1,true)and failure=='check'then return false end;return true end
 local env=setmetatable({M=M,fail=function(s)error(s,0)end,service=function(action)
  events[#events+1]=action
  if action=='start'and failure=='start'and not started then started=true;error('fixture start failed')end
  if action=='start'and failure~='none'then assert(files['C/configs/policy.tsv']=='OLD POLICY','restore policy before restarting old configuration')end
 end,dofile=function(p)
  if p:find('config-normalize',1,true)then return {normalize=function()end}end
  if p:find('mihomo',1,true)then return {build=function(c)assert(c._subscription_policy=='NEW POLICY');assert(files['C/configs/policy.tsv']=='OLD POLICY','staging must not overwrite saved policy');return {} end}end
  error('unexpected fixture import: '..p)
 end,os={remove=function(p)files[p]=nil end,rename=function(a,b)files[b]=files[a];files[a]=nil;return true end}}, {__index=_G})
 local chunk=assert(loadstring(fn));setfenv(chunk,env);local publish=chunk()
 local ok=pcall(publish,{outbounds={},_native_meta={},_subscription_policy='NEW POLICY'})
 if failure=='none'then
  assert(ok and files['C/configs/policy.tsv']=='NEW POLICY')
  assert(not json.decode(files['C/configs/config.json'])._subscription_policy,'staged metadata must not leak into published config')
 else assert(not ok and files['C/configs/config.json']=='OLD'and files['C/configs/policy.tsv']=='OLD POLICY')end
end
print('subscription commit: staged validation, atomic policy/config publication, check/start rollback passed')
