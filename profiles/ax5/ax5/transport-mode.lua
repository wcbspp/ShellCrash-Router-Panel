-- ShellCrash owns the setting and service entry; the AX5 adapter owns its hooks.
local M=dofile('/data/ShellCrash/ax5/common.lua')
local T={}
local tool='/data/ShellCrash-tool'
local names={redir='Redir模式',mixed='混合模式'}
function T.configured()
 local value=('\n'..M.read(tool..'/configs/ShellCrash.cfg')):match('\nredir_mod=([^\r\n]+)') or names.redir
 for key,name in pairs(names)do if value==name then return key end end
 return 'unsupported'
end
function T.capable()
 return M.read(M.C..'/cache/core.env'):match('KIND=meta[%s]')~=nil and M.run('test -c /dev/net/tun') and M.read('/proc/net/ip_tables_targets'):match('%f[%w]MARK%f[%W]')~=nil
end
function T.state()
 return {configured=T.configured(),active=M.read(M.R..'/transport-runtime'):gsub('%s+$',''),mixed_available=T.capable()}
end
function T.tun()
 local mode=T.configured();assert(mode~='unsupported','当前接管方式未适配，请在 ShellCrash 中选择 Redir 或混合模式')
 if mode~='mixed'then return {enable=false}end
 return {enable=true,stack='system',device='utun',['auto-route']=false,['auto-redirect']=false,['auto-detect-interface']=false,mtu=1500}
end
local function set(mode)
 assert(names[mode],'invalid_transport_mode')
 assert(M.run('CRASHDIR='..tool..'; export CRASHDIR; . "$CRASHDIR/libs/set_config.sh"; setconfig redir_mod '..M.quote(names[mode])),'接管方式保存失败，原设置保留')
 assert(T.configured()==mode,'接管方式保存后校验失败')
end
function T.apply(mode,service,phase)
 assert(names[mode],'invalid_transport_mode')
 local before=T.configured();assert(names[before],'当前接管方式未适配，请先恢复 Redir 模式')
 local running=M.pid()>0
 local traffic=M.read(M.R..'/traffic-mode'):gsub('%s+$','')
 if mode==before and (not running or M.read(M.R..'/transport-runtime'):gsub('%s+$','')==mode)then return '接管方式未变化，无需重启'end
 if mode=='mixed'then
  assert(T.capable(),'当前内核或固件不支持混合模式，原设置保留')
  assert((M.memory().MemAvailable or 0)>=M.limits().protect_mb*1024,'memory_protected')
  assert(before=='mixed' or M.read('/sys/class/net/utun/ifindex')=='','utun 已被其他服务使用，原设置保留')
  assert(M.exec('ip rule show'):find('lookup 21313',1,true)==nil,'策略路由表 21313 已被占用，原设置保留')
 end
 phase('working',running and '正在通过 ShellCrash 切换并重启服务' or '正在保存下次启动的接管方式',true)
 local ok,err=pcall(function()
  set(mode)
  if running then
   service('restart')
   assert(M.read(M.R..'/transport-mode'):gsub('%s+$','')==mode,'接管规则未生效')
   if traffic=='direct'or traffic=='global'then dofile(M.C..'/ax5/traffic-mode.lua').apply(traffic)end
  end
 end)
 if not ok then
  local restored=pcall(function()
   set(before)
   if running then
    service('restart')
    if traffic=='direct'or traffic=='global'then dofile(M.C..'/ax5/traffic-mode.lua').apply(traffic)end
   end
  end)
  error(restored and ('切换失败，已恢复原接管方式：'..tostring(err)) or ('切换及回退未完成，请查看运行日志：'..tostring(err)),0)
 end
 return running and '接管方式已生效，ShellCrash 已重启' or '接管方式已保存，下次启动生效'
end
return T
