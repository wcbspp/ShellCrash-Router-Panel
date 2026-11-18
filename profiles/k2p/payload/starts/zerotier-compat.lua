-- Firmware paths and lifecycle only; policy and transaction live in shared/.
local C='/etc/storage/ShellCrash'
local M={C=C,R='/tmp/sc-admin'}
os.execute('mkdir -p /tmp/sc-admin')
local adapter={path='/var/lib/zerotier-one/local.conf',prefix='utun',allow_missing=true,
 available=function()return M.run('sh '..C..'/starts/zerotier-service.sh probe')end,
 restart=function()return M.run('sh '..C..'/starts/zerotier-service.sh start')end,
 persist=function()return M.run('sh '..C..'/starts/zerotier-service.sh save')end}
local Z=assert(loadfile(C..'/starts/zerotier-compat-core.lua'))(M,adapter)
local action=arg and arg[1]
if action=='status'then
 local status=Z.status()
 status.monitor=assert(loadfile(C..'/starts/zerotier-monitor.lua'))(M,'/usr/bin/zerotier-cli','/usr/bin/zerotier-one','/var/lib/zerotier-one')
 print(M.json.encode(status))
elseif action=='enforce'then Z.enforce()
elseif action=='finish'then Z.finish()
elseif action=='set'then assert(arg[2]=='0'or arg[2]=='1','invalid_zerotier_setting');Z.set(arg[2]=='1',false)
end
return Z
