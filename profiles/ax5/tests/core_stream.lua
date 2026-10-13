local original=dofile
local M={C='/fixture'}
function M.read()return 'Authorization: Bearer fixture'end
function M.quote(s)return "'"..s.."'"end
_G.dofile=function(p)if p:match('common.lua$')then return M end;return original(p)end
local real_popen=io.popen
local response,closed
io.popen=function(cmd)
 assert(cmd:find('127.0.0.1:9999',1,true));assert(cmd:find('--max-time 10',1,true))
 local line,pos=0,1;closed=false
 return {read=function(_,count)
  if count=='*l'then line=line+1;return response.headers[line]end
  if pos>#response.body then return nil end
  local value=response.body:sub(pos,pos+count-1);pos=pos+#value;return value
 end,close=function()closed=true end}
end
local S=original(arg[1]or'/data/ShellCrash/ax5/core-stream.lua')
response={headers={'HTTP/1.1 200 OK\r','Transfer-Encoding: chunked\r','\r'},body=string.rep('x',5000)}
local file='/tmp/sc-stream-fixture';local ok,status=S.fetch('/rules',file,1000);assert(not ok and status==413 and closed and not io.open(file))
response.body='{"rows":[]}';ok,status=S.fetch('/version',file,1000);assert(ok and status==200 and closed);local f=assert(io.open(file));assert(f:read('*a')==response.body);f:close();os.remove(file)
response={headers={'HTTP/1.1 401 Unauthorized\r','\r'},body=''};local p,status=S.open('/configs');assert(not p and status==401 and closed)
response={headers={'invalid','\r'},body=''};p,status=S.open('/configs');assert(not p and status==503 and closed)
io.popen=real_popen;_G.dofile=original
print('core stream: hard byte cap without Content-Length, preserved bytes, HTTP errors and malformed headers passed')
