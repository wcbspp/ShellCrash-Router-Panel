-- Reuse the existing minute timer for ShellCrash conservative mode.
local M=dofile('/data/ShellCrash/ax5/common.lua')
if not M.read('/data/ShellCrash-tool/configs/ShellCrash.cfg'):match('\nstart_old=ON[\r\n]') and
 not M.read('/data/ShellCrash-tool/configs/ShellCrash.cfg'):match('^start_old=ON[\r\n]') then return end
if M.read(M.C..'/configs/enabled'):match('^%s*1%s*$')==nil then return end
if M.pid()>0 then os.remove(M.R..'/watchdog-retry.json');return end
local fs=require('nixio.fs')
if fs.stat(M.R..'/manual-stop') or fs.stat(M.R..'/operation.lock') then return end
if M.load(M.R..'/job.json').active then return end
local now=os.time();local retry=M.load(M.R..'/watchdog-retry.json',{attempts=0,next=0})
if now<(tonumber(retry.next)or 0) or not M.lock('watchdog.lock',120) then return end
local ok,err=pcall(function()
 -- Check again after acquiring the lock; the web/CLI may have started meanwhile.
 if M.pid()>0 or fs.stat(M.R..'/manual-stop') or fs.stat(M.R..'/operation.lock') then return end
 retry.attempts=(tonumber(retry.attempts)or 0)+1
 retry.next=now+math.min(retry.attempts*60,300)
 M.save(M.R..'/watchdog-retry.json',retry)
 M.run('SC_CONTROL_SOURCE=watchdog '..M.C..'/ax5/cli.sh watchdog >> '..M.R..'/service.log 2>&1')
end)
M.run('rmdir '..M.quote(M.R..'/watchdog.lock')..' 2>/dev/null');os.remove(M.R..'/watchdog.lock.time')
if not ok then error(err) end
