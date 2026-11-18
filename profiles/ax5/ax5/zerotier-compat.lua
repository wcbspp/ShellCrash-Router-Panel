local M=dofile('/data/ShellCrash/ax5/common.lua')
local home,binary='/opt/var/lib/zerotier-one','/opt/bin/zerotier-one'
local adapter={home=home,binary=binary,path=home..'/local.conf',prefix='utun',
 available=function()return M.read('/opt/etc/init.d/S27zerotier',2)~=''end,
 restart=function()return M.run('/opt/etc/init.d/S27zerotier restart >/dev/null 2>&1')end}
local Z=assert(loadfile(M.C..'/ax5/zerotier-compat-core.lua'))(M,adapter)
function Z.monitor()
 return assert(loadfile(M.C..'/ax5/zerotier-monitor.lua'))(M,'/opt/bin/zerotier-cli',binary,home)
end
if arg and arg[1]=='enforce'then Z.enforce()elseif arg and arg[1]=='finish'then Z.finish()end
return Z
