local M=dofile(arg[1] or '/data/ShellCrash/ax5/common.lua')
local function stat(ticks)
 local f={'S'};for i=2,19 do f[i]='0' end;f[20]=tostring(ticks)
 return '42 (a tricky ) name) '..table.concat(f,' ')
end
local content={['/proc/uptime']='90061.75 0', ['/proc/42/stat']=stat(100)}
M.read=function(p)return content[p] or '' end
assert(M.core_uptime(42)==90060)
content['/proc/42/stat']=stat(9006000);assert(M.core_uptime(42)==1)
content['/proc/42/stat']='broken';assert(M.core_uptime(42)==nil)
content['/proc/42/stat']=stat(9006200);assert(M.core_uptime(42)==nil)
assert(M.core_uptime(0)==nil)
print('core uptime: 5 checks passed')
