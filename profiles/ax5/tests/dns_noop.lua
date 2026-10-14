-- Exercise the real job with isolated filesystem/API mocks, never router settings.
local source=arg[1]or'/data/ShellCrash/ax5/job.lua'
for _,valid in ipairs({true,false})do
 local filter='# fixture\n+.example.com\n';local files={};local phases={};local commands={}
 local M={C='/fixture',R='/fixture/tmp',memory=function()return{MemAvailable=24000}end,limits=function()return{protect_mb=14}end,
  read=function(p)
   if p:match('/upload%-id%-filter$')then return'test'end
   if p:match('/upload%-filter$')or p:match('/fake_ip_filter.list$')then return filter end
   if p:match('/dns%-mode$')then return'mix\n'end
   return files[p]or''
  end,
  load=function(p)if p:match('/request.json$')then return{action='dns',args={'test','mix'}}end;error('unexpected config allocation: '..p)end,
  write=function(p,s)files[p]=s end,b64=function(s)return s end,
  save=function(p,d)if p:match('/job.json$')then phases[#phases+1]=d end end,
  run=function(cmd)commands[#commands+1]=cmd;return valid end}
 local f=assert(loadfile(source));setfenv(f,setmetatable({dofile=function(p)assert(p=='/data/ShellCrash/ax5/common.lua');return M end},{__index=_G}));f()
 assert(#commands==1 and commands[1]:find('filter_compile.awk',1,true))
 if valid then assert(phases[#phases].phase=='done'and phases[#phases].message_b64:find('无需重启',1,true))
 else assert(phases[#phases].phase=='error'and phases[#phases].message_b64=='invalid_filter_previous_kept')end
 assert(not files['/fixture/configs/config.json']and not files['/fixture/configs/fake_ip_filter.list'])
end
print('DNS unchanged save: validates filter, skips config allocation/restart/remote backup; invalid input still rejected')
