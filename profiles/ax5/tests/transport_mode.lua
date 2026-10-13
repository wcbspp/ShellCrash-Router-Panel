local original=dofile
local source=arg[1]or'/data/ShellCrash/ax5/transport-mode.lua'
local function fixture(options)
 options=options or{};local files={['/data/ShellCrash-tool/configs/ShellCrash.cfg']='other=keep\nredir_mod=Redir模式\n',['/fixture/cache/core.env']='KIND=meta\n',['/proc/net/ip_tables_targets']='MARK\n',['/ram/transport-runtime']='redir\n',['/ram/transport-mode']='redir\n',['/ram/traffic-mode']='rule\n'}
 local calls={};local M={C='/fixture',R='/ram',read=function(p)return files[p]or''end,quote=function(s)return "'"..s.."'"end,pid=function()return options.stopped and 0 or 1 end,memory=function()return {MemAvailable=options.low and 100 or 20000}end,limits=function()return {protect_mb=12}end,exec=function()return options.conflict and '21313: lookup 21313' or''end}
 M.run=function(s)
  if s=='test -c /dev/net/tun'then return not options.unsupported end
  calls[#calls+1]=s
  local mode=s:match("setconfig redir_mod '([^']+)'")
  assert(mode,'must use official ShellCrash setconfig')
  files['/data/ShellCrash-tool/configs/ShellCrash.cfg']='other=keep\nredir_mod='..mode..'\n';return true
 end
 dofile=function(p)if p:match('/common.lua$')then return M elseif p:match('/traffic%-mode.lua$')then return {apply=function(mode)calls[#calls+1]='traffic:'..mode end}end;error(p)end
 local T=original(source)
 local count=0
 local function service(action)
  calls[#calls+1]=action;count=count+1
  if options.fail and count==1 then error('fixture startup failed')end
  local mode=T.configured();files['/ram/transport-runtime']=mode..'\n';files['/ram/transport-mode']=mode..'\n'
 end
 return T,files,calls,service
end
local T,f,c,s=fixture();assert(T.tun().enable==false);assert(T.apply('mixed',s,function()end):find('已重启'));assert(T.configured()=='mixed');assert(T.tun().stack=='system'and T.tun()['auto-route']==false);assert(f['/data/ShellCrash-tool/configs/ShellCrash.cfg']:find('other=keep'));assert(c[2]=='restart');local n=#c;assert(T.apply('mixed',s,function()end):find('无需重启'));assert(#c==n)
T,f,c,s=fixture({fail=true});assert(not pcall(T.apply,'mixed',s,function()end));assert(T.configured()=='redir');assert(c[4]=='restart','failed new mode must restart original mode');assert(f['/ram/transport-runtime']=='redir\n')
for _,options in ipairs({{low=true},{unsupported=true},{conflict=true}})do T,f,c,s=fixture(options);assert(not pcall(T.apply,'mixed',s,function()end));assert(T.configured()=='redir'and #c==0,'rejected mode must not mutate or restart')end
T,f,c,s=fixture({stopped=true});assert(T.apply('mixed',s,function()end):find('下次启动'));assert(#c==1,'saving while stopped must not start the service')
T,f,c,s=fixture();f['/ram/traffic-mode']='global\n';T.apply('mixed',s,function()end);assert(c[3]=='traffic:global','preserve global/rule choice across restart')
T,f,c,s=fixture();assert(not pcall(T.apply,'bad;touch file',s,function()end));assert(#c==0)
dofile=original
print('transport: official setting/restart, no-op, rollback, capability/memory/route rejection, stopped save and flow-mode preservation passed')
