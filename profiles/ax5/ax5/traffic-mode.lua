local M=dofile('/data/ShellCrash/ax5/common.lua')
local T={}
function T.apply(mode)
 assert(({rule=true,direct=true,global=true})[mode],'invalid_mode')
 assert(M.pid()>0,'core_not_running')
 local raw,status=M.request('/configs');assert(status==200,'core_unavailable')
 local before=M.json.decode(raw);local previous=tostring(before.mode or 'rule'):lower()
 assert(({rule=true,direct=true,global=true})[previous],'invalid_core_mode')
 local _,code=M.request('/configs','PATCH',M.json.encode({mode=mode}))
 local ok=code>=200 and code<300 and M.run(M.C..'/ax5/firewall.sh '..(mode=='direct'and'stop'or'start')..' >> '..M.R..'/service.log 2>&1')
 if ok then
  local current,readstatus=M.request('/configs');local readok,d=pcall(M.json.decode,current)
  ok=readstatus==200 and readok and tostring(d.mode):lower()==mode
 end
 if not ok then
  M.request('/configs','PATCH',M.json.encode({mode=previous}))
  M.run(M.C..'/ax5/firewall.sh '..(previous=='direct'and'stop'or'start')..' >> '..M.R..'/service.log 2>&1')
  error('模式切换失败，已尝试恢复原接管模式')
 end
 M.write(M.R..'/traffic-mode',mode..'\n')
 M.run('pids=$(pidof dnsmasq); [ -z "$pids" ] || kill -HUP $pids')
 return true
end
return T
