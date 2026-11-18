local M=dofile('/data/ShellCrash/ax5/common.lua')
local home,binary='/opt/var/lib/zerotier-one','/opt/bin/zerotier-one'
local init='/opt/etc/init.d/S27zerotier'
local function configured_home()
 local script=M.read(init,4097)
 if #script>4096 then return nil end
 local args,procs,preargs
 for line in script:gmatch('[^\n]+') do
  if line:match('^%s*ARGS%s*=') then
   if args then return nil end
   args=line:match('^%s*ARGS="([^"]*)"%s*$')
   if not args then return nil end
  elseif line:match('^%s*PROCS%s*=') then
   if procs or not line:match('^%s*PROCS=zerotier%-one%s*$') then return nil end
   procs=true
  elseif line:match('^%s*PREARGS%s*=') then
   if preargs or not line:match('^%s*PREARGS=""%s*$') then return nil end
   preargs=true
  end
 end
 if not procs or not preargs then return nil end
 if args=='-d' then return home end
 return args and args:match('^%-d%s+(/[A-Za-z0-9_./-]+)$')
end
local adapter={home=home,binary=binary,path=home..'/local.conf',prefix='utun',configured_home=configured_home,
 available=function()return M.read('/opt/etc/init.d/S27zerotier',2)~=''end,
 restart=function()return M.run('/opt/etc/init.d/S27zerotier restart >/dev/null 2>&1')end}
local Z=assert(loadfile(M.C..'/ax5/zerotier-compat-core.lua'))(M,adapter)
function Z.monitor()
 return assert(loadfile(M.C..'/ax5/zerotier-monitor.lua'))(M,'/opt/bin/zerotier-cli',binary,Z.home)
end
if arg and arg[1]=='enforce'then Z.enforce()elseif arg and arg[1]=='finish'then Z.finish()end
return Z
