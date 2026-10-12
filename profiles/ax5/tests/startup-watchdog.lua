-- Run with Lua on the router; all process/filesystem operations are mocks.
local target=arg[1] or '/data/ShellCrash/ax5/watchdog.lua'
local cases={
 {mode='OFF'}, {enabled='0'}, {pid=42}, {manual=true}, {operation=true},
 {job=true}, {next=200}, {locked=true}, {expected=1}, {raced=true}
}
local real_dofile=dofile
for _,case in ipairs(cases) do
 local calls=0;local saved;local lock_seen=false
 local M={C='/persist',R='/ram'}
 function M.read(p)
  if p:match('ShellCrash.cfg$')then return 'start_old='..(case.mode or 'ON')..'\n' end
  if p:match('/enabled$')then return case.enabled or '1\n' end
  return ''
 end
 function M.pid()return case.pid or (case.raced and lock_seen and 42) or 0 end
 function M.load(p,default)
  if p:match('job.json$')then return {active=case.job}end
  return {next=case.next or 0,attempts=0}
 end
 function M.lock()lock_seen=true;return not case.locked end
 function M.save(_,v)saved=v end
 function M.quote(v)return v end
 function M.run(command)if command:find('cli.sh watchdog',1,true)then calls=calls+1 end;return true end
 local old_time=os.time;os.time=function()return 100 end
 local old_remove=os.remove;os.remove=function()return true end
 local old_require=require
 require=function(name)
  if name=='nixio.fs'then return {stat=function(p)
   if p:match('manual%-stop$')then return case.manual end
   if p:match('operation.lock$')then return case.operation end
  end}end
  return old_require(name)
 end
 dofile=function()return M end
 local ok,err=pcall(real_dofile,target)
 dofile=real_dofile;require=old_require;os.time=old_time;os.remove=old_remove
 assert(ok,err);assert(calls==(case.expected or 0),'unexpected start')
 if case.expected then assert(saved.next==160 and saved.attempts==1,'missing retry backoff')end
end
print('10 conservative watchdog isolation checks passed')
