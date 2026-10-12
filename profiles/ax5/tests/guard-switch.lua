-- Guard changes preserve startup flags and restore the previous mode on failure.
local target=arg[1]or'/data/ShellCrash/ax5/job.lua'
local real_dofile=dofile
for _,case in ipairs({{mode='conservative'},{mode='procd'},{mode='invalid',error=true},{mode='procd',stopped=true},{mode='conservative',failure=true,error=true}})do
 local pid=case.stopped and 0 or 42;local cfg='start_old=OFF\n';local old=cfg;local job;local starts=0
 local M={C='/persist',R='/ram'}
 function M.load(p)if p:match('request.json$')then return{action='guard',args={'aabbccdd',case.mode}}end;return{}end
 function M.read()return cfg end
 function M.write(p,v)if p:match('ShellCrash.cfg$')then cfg=v end end
 function M.b64(v)return v end
 function M.save(_,v)job=v end
 function M.pid()return pid end
 function M.api()return '{}'end
 function M.run(cmd)
  if cmd:find('setconfig start_old',1,true)then cfg='start_old='..cmd:match('start_old (%u+)')..'\n'
  elseif cmd:find('start.sh stop',1,true)then pid=0
  elseif cmd:find('start.sh start',1,true)then starts=starts+1;if case.failure and starts==1 then return false end;pid=42 end
  return true
 end
 local old_remove=os.remove;os.remove=function()return true end
 dofile=function()return M end
 real_dofile(target);dofile=real_dofile;os.remove=old_remove
 assert(job.phase==(case.error and'error'or'done'),'incorrect result')
 if case.error then assert(cfg==old,'prior setting not restored')else assert(cfg=='start_old='..(case.mode=='conservative'and'ON'or'OFF')..'\n')end
 assert(pid==(case.stopped and 0 or 42),'service running/stopped state changed')
 assert(not case.stopped or starts==0,'stopped service restarted')
end
print('guard switch: 5 cases passed')
