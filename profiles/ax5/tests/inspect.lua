local real_dofile=dofile
local data,available,live,run_ok,called={},40000,42,true,0
local M={C='/test',R='/tmp',json=require('cjson')}
function M.load()return {}end
function M.lock()return true end
function M.pid()return live end
function M.memory()return {MemAvailable=available}end
function M.limits()return {protect_mb=14}end
function M.read(path)if path:find('inspect-',1,true)then return M.json.encode(data)end;return 'Authorization: Bearer fixture' end
function M.run(cmd)if cmd:match('^rmdir ')then return true end;called=called+1;assert(not cmd:find('fixture-password',1,true));if run_ok then local path=cmd:match("%-o '([^']+)'");local f=assert(io.open(path,'wb'));f:write(M.json.encode(data));f:close()end;return run_ok end
function M.quote(s)return "'"..s.."'"end
_G.dofile=function(p)if p:match('common.lua$')then return M end;return real_dofile(p)end
local I=real_dofile(arg[1]or'/data/ShellCrash/ax5/inspect.lua')
data={rules={}};for n=1,45 do data.rules[n]={type='DOMAIN',payload='site'..n..'.example',proxy='Proxy'}end
data.rules[36].payload=string.rep('x',8000)..' \" } { ';data.rules[2].payload='braces { } and \"quotes\" and \\ paths';local d=assert(I.query('rules',1,''));assert(d.total==45 and #d.rows==20 and d.rows[1].order==21)
d=assert(I.query('rules',0,'site45'));assert(d.total==1 and d.rows[1].order==45)
data={proxies={B={all={'n1'},now='n1',password='fixture-password'},A={all={'n2'}},n1={type='AnyTLS'}}}
d=assert(I.query('groups',0,''));assert(d.total==2 and d.rows[1].title=='A' and not M.json.encode(d):find('fixture-password',1,true))
data={connections={{metadata={host='site.example',sourceIP='10.0.0.2',network='tcp'},chains={'Proxy'},rule='Domain'}}}
d=assert(I.query('connections',0,''));assert(d.total==1 and d.rows[1].title=='site.example')
local count=called;available=17000;assert(not I.query('rules',0,''));assert(called==count)
available=40000;live=0;assert(not I.query('rules',0,''));assert(called==count)
live=42;assert(not I.query('unknown',0,''));assert(not I.query('rules',-1,''));assert(not I.query('rules',0,string.rep('x',129)));assert(called==count)
data={rules={{payload=string.rep('x',17000)}}};assert(not I.query('rules',0,''));run_ok=false;assert(not I.query('rules',0,''));M.lock=function()return false end;assert(not I.query('rules',0,''))
print('inspection: pagination, search, group sorting, connection display, credential omission and refusal checks passed')
