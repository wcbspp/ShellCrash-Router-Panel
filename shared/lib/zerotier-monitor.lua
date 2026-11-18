-- Collect a bounded read-only snapshot using the local ZeroTier CLI.
local M, cli, daemon, home = ...
local monitor = {installed = M.run('test -x '..M.quote(cli)..' || test -x '..M.quote(daemon))}
if not monitor.installed then return monitor end

monitor.networks = {}
local function query(action)
 local command = M.quote(cli)..' '..M.quote('-D'..home)..' '..action
 return M.exec('('..command..' 2>/dev/null & child=$!; '
  ..'(sleep 3; kill "$child" 2>/dev/null) </dev/null >/dev/null & timer=$!; '
  ..'wait "$child"; kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null) 2>/dev/null | head -c 8192')
end

if M.exec('pidof zerotier-one 2>/dev/null'):match('%d') then
 local info = query('info')
 monitor.version, monitor.status = info:match('200 info %x+ (%S+) ([A-Z_]+)')
 if monitor.status then
  for line in query('listnetworks'):gmatch('[^\n]+') do
   local id, status, device, ips = line:match('^200 listnetworks (%x+) .- [%x:]+ ([A-Z_]+) [A-Z]+ ([%w_-]+) (.+)$')
   if id and #id == 16 and #monitor.networks < 16 then
    monitor.networks[#monitor.networks+1] = {id=id,status=status,device=device,ips=ips:sub(1,256)}
   end
  end
 end
 monitor.status = monitor.status or 'UNAVAILABLE'
else
 monitor.status = 'STOPPED'
end

local path = M.R..'/zerotier-diagnostic'
local rows = {}
for line in M.read(path,8192):gmatch('[^\n]+') do rows[#rows+1] = line end
while #rows >= 30 do table.remove(rows,1) end
rows[#rows+1] = os.date('%Y-%m-%d %H:%M:%S')..' '..monitor.status..' | networks='..#monitor.networks
monitor.log = table.concat(rows,'\n')
pcall(M.write,path,monitor.log..'\n')
return monitor
