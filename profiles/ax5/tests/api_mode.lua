local json=require('cjson');local source=arg[1]or'/data/ShellCrash/ax5/api.lua'
local token='fixture-token-longer-than-16'
local cases={
 {'POST','/configs',{mode='direct'},token,200,1},
 {'PATCH','/configs',{mode='global'},token,200,1},
 {'POST','/configs',{mode='rule',secret='forbidden'},token,400,0},
 {'POST','/configs',{mode='invalid'},token,400,0},
 {'POST','/configs',{mode='rule'},'wrong',403,0},
 {'PATCH','/proxies/GLOBAL',{mode='rule'},token,403,0},
 {'POST','/version',{mode='rule'},token,403,0},
}
for _,case in ipairs(cases)do
 local status,calls=0,0
 local H={getenv=function(k)if k=='REQUEST_METHOD'then return case[1]elseif k=='HTTP_X_SC_CSRF'then return case[4]elseif k=='CONTENT_LENGTH'then return '64'end end,
 formvalue=function(k)if k=='path'then return case[2]elseif k=='payload'then return json.encode(case[3])end end,
 status=function(n)status=n end,header=function()end,prepare_content=function()end,write=function()end}
 local M={C='C',R='R',json=json,lock=function()return true end,read=function()return token end,request=function(p,m,b)
  calls=calls+1;assert(p=='/configs'and m=='PATCH');local v=json.decode(b);assert(v.mode==case[3].mode);return '',204
 end}
 local f=assert(loadfile(source));setfenv(f,setmetatable({dofile=function(p)if p:find('traffic-mode.lua',1,true)then return {apply=function(mode)calls=calls+1;assert(mode==case[3].mode)end}end;return M end,require=function(n)if n=='luci.http'then return H elseif n=='luci.dispatcher'then return {}end;error(n)end},{__index=_G}))
 local A=f();A.api();assert(status==case[5],case[1]..' '..case[2]..' status '..status);assert(calls==case[6],'rejected requests must not reach core')
end
print('mode API: POST transport, strict mode-only update, CSRF and path restriction passed')
