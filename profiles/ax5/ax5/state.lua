local M=dofile('/data/ShellCrash/ax5/common.lua')
local action=arg[1]
local function selections(proxies)
 local p={};for tag,v in pairs(proxies or{})do if v.type=='Selector' and v.now then p[tag]=v.now end end;return p
end
local function different(a,b)
 for k,v in pairs(a)do if b[k]~=v then return true end end
 for k,v in pairs(b)do if a[k]~=v then return true end end
 return false
end
if action=='incident' then
 local text=M.exec('dmesg | tail -80');local pid=arg[2];local code=tonumber(arg[3]) or 0
 local reason='unknown'
 if text:match('Killed process '..pid..'%D') or text:match('Kill process '..pid..'%D') then reason='oom' end
 local mem=M.memory().MemAvailable or 0
 local lines=M.read(M.R..'/incidents')..os.date('%Y-%m-%d %H:%M:%S')..'|'..os.date('%Y-%m-%d %H:%M:%S')..'|'..reason..'|'..pid..'|0|'..mem..'|pending|'..code..'\n'
 local list={};for l in lines:gmatch('[^\n]+')do list[#list+1]=l end;while #list>100 do table.remove(list,1)end;M.write(M.R..'/incidents',table.concat(list,'\n')..'\n')
 local events=M.load(M.R..'/events.json',{events={}});events.events[#events.events+1]={time=os.time(),pid=tonumber(pid),exit_code=code,reason=reason,memory_kb=mem};while #events.events>100 do table.remove(events.events,1)end;M.save(M.R..'/events.json',events)
 M.write(M.R..'/last-exit.txt','exit_code='..code..'\npid='..pid..'\n'..text)
elseif action=='save-selection' then
 if M.pid()==0 then return end
 local ok,d=pcall(M.json.decode,M.api('/proxies'))
 if ok and d.proxies then
  local p=selections(d.proxies);local changed=different(p,M.load(M.C..'/configs/selectors.json'))
  if changed then M.save(M.R..'/selectors.json',p);M.save(M.C..'/configs/selectors.json',p)end
 end
elseif action=='sample' then
 dofile(M.C..'/ax5/watchdog.lua')
 if not M.lock('sample.lock',300)then return end
 local ok,err=pcall(function()
  M.trimlogs()
  local s=M.state();local now=os.time();local up=tonumber(M.read('/proc/uptime'):match('^[%d.]+')) or 0
  local rows={};for l in M.read(M.R..'/memory.csv'):gmatch('[^\n]+')do rows[#rows+1]=l end
  rows[#rows+1]=table.concat({now,math.floor(up),s.pid,s.rss_kb,s.available_kb,s.conntrack},',');while #rows>1441 do table.remove(rows,1)end;M.write(M.R..'/memory.csv',table.concat(rows,'\n')..'\n')
  local job=M.load(M.R..'/job.json');if not job.active and (s.memory_limits.cleanup_mb>0 and s.available_kb<s.memory_limits.cleanup_mb*1024)then M.cleanup(false)end
  if s.running then
   local p=M.load(M.R..'/selectors.json');local raw=M.api('/proxies');local good,data=pcall(M.json.decode,raw)
   if good then
    local next=selections(data.proxies);local changed=different(next,p);p=next
    if changed then M.save(M.R..'/selectors.json',p);M.save(M.C..'/configs/selectors.json',p) end
   end
  end
 end)
 os.remove(M.R..'/sample.lock');if not ok then M.write(M.R..'/sample-error',tostring(err))end
elseif action=='restore' then
 local good,data=pcall(M.json.decode,M.api('/proxies'));local proxies=good and data.proxies or{}
 for tag,name in pairs(M.load(M.C..'/configs/selectors.json'))do if proxies[tag] and proxies[tag].type=='Selector' then M.api('/proxies/'..tag:gsub('([^%w%-_%.~])',function(x)return string.format('%%%02X',x:byte())end),'PUT',M.json.encode({name=name}))end end
 local incidents=M.read(M.R..'/incidents');if incidents:match('|pending|[%d]+\n$')then M.write(M.R..'/incidents',incidents:gsub('|pending|(%d+)\n$','|restored|%1\n'))end
 local events=M.load(M.R..'/events.json',{events={}});if #events.events>0 and not events.events[#events.events].restored then events.events[#events.events].restored=os.time();M.save(M.R..'/events.json',events)end
end
