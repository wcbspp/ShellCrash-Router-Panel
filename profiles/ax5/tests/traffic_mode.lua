local json=require('cjson');local source=arg[1]or'/data/ShellCrash/ax5/traffic-mode.lua'
for _,case in ipairs({{'direct',false},{'global',false},{'global',true}})do
 local mode='rule';local files={};local calls={};local failed=false
 local M={C='/fixture',R='/fixture/tmp',json=json,pid=function()return 10 end,write=function(p,s)files[p]=s end,request=function(path,method,body)
  if method=='PATCH'then mode=json.decode(body).mode;calls[#calls+1]='api:'..mode;return '',204 end
  return json.encode({mode=mode}),200
 end,run=function(cmd)
  if cmd:find('firewall.sh',1,true)then
   calls[#calls+1]='fw:'..(cmd:find(' stop',1,true)and'stop'or'start')
   if case[2]and not failed then failed=true;return false end
  end
  return true
 end}
 local f=assert(loadfile(source));setfenv(f,setmetatable({dofile=function()return M end},{__index=_G}));local T=f()
 local ok=pcall(T.apply,case[1]);assert(ok~=case[2]);assert(calls[1]=='api:'..case[1])
 if ok then assert(mode==case[1]);assert(files['/fixture/tmp/traffic-mode']==mode..'\n');assert(calls[2]=='fw:'..(mode=='direct'and'stop'or'start'))
 else assert(mode=='rule');assert(calls[3]=='api:rule');assert(not files['/fixture/tmp/traffic-mode'])end
end
print('traffic mode: API/firewall coupling, direct interception stop and failed firewall rollback passed')
