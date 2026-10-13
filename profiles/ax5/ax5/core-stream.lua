local M=dofile('/data/ShellCrash/ax5/common.lua')
local S={}
-- Read trusted loopback HTTP headers, then relay small body chunks. Avoid a
-- full JSON/Lua clone for large rule and connection lists on 128 MB devices.
function S.open(path)
 local header=M.read(M.C..'/configs/api-header'):gsub('%s+$','')
 local p=io.popen('curl --noproxy "*" -i -fsSN --connect-timeout 2 --max-time 10 -H '..M.quote(header)..' '..M.quote('http://127.0.0.1:9999'..path)..' 2>/dev/null','r')
 if not p then return nil,503 end
 local first=p:read('*l')or'';local code=tonumber(first:match('^HTTP/%S+ (%d%d%d)'))
 local bytes=#first;local ended=false
 for _=1,40 do
  local line=p:read('*l');if not line then break end;bytes=bytes+#line
  if bytes>8192 then break end
  if line==''or line=='\r'then ended=true;break end
 end
 if not code or not ended or code<200 or code>=300 then p:close();return nil,code or 503 end
 return p,code
end
function S.fetch(path,destination,limit)
 local p,code=S.open(path);if not p then return false,code end
 local f=io.open(destination,'wb');if not f then p:close();return false,500 end
 local total,ok=0,true
 while true do
  local block=p:read(4096);if not block then break end
  total=total+#block;if total>limit then ok=false;code=413;break end
  if not f:write(block)then ok=false;code=500;break end
 end
 f:close();p:close()
 if not ok then os.remove(destination)end
 return ok,code
end
return S
