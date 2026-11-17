local M=dofile('/data/ShellCrash/ax5/common.lua')
local adapter={path='/opt/var/lib/zerotier-one/local.conf',prefix='utun',
 available=function()return M.read('/opt/etc/init.d/S27zerotier',2)~=''end,
 restart=function()return M.run('/opt/etc/init.d/S27zerotier restart >/dev/null 2>&1')end}
local Z=assert(loadfile(M.C..'/ax5/zerotier-compat-core.lua'))(M,adapter)
if arg and arg[1]=='enforce'then Z.enforce()elseif arg and arg[1]=='finish'then Z.finish()end
return Z
