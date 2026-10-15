local M=dofile('/data/ShellCrash/ax5/common.lua')
M.write(M.R..'/operation.lock/owner',tostring(require('nixio').getpid()))
local req=M.load(M.R..'/request.json');local args=req.args or {};local id=args[1]or''
os.remove(M.R..'/last-job-error')
local function phase(p,msg,active,extra)
 local history={};for line in M.read(M.R..'/operations.log',32768):gmatch('[^\n]+')do history[#history+1]=line end
 local safe=tostring(msg):gsub('https?://[^%s]+','[链接已隐藏]'):gsub('[\r\n]',' ')
 history[#history+1]=os.date('%Y-%m-%d %H:%M:%S')..' | '..(req.action or'')..' | '..p..' | '..safe
 while #history>100 do table.remove(history,1)end;M.write(M.R..'/operations.log',table.concat(history,'\n')..'\n')
 local d={id=id,phase=p,active=active,message_b64=M.b64(msg)};for k,v in pairs(extra or {})do d[k]=v end;M.save(M.R..'/job.json',d)
end
local function fail(msg) error(msg,0)end
local function service(action)
 if action=='restart'then service('stop');service('start');return end
 if action=='stop'then M.write(M.C..'/configs/enabled','0\n')else M.write(M.C..'/configs/enabled','1\n')end
 if not M.run('SC_CONTROL_SOURCE=panel /data/ShellCrash-tool/start.sh '..action..' >> '..M.R..'/service.log 2>&1')then fail('service_'..action..'_failed')end
 if action=='stop'then for i=1,15 do if M.pid()==0 then return end;M.run('sleep 1')end;fail('service_stop_failed')end
 if action~='stop'then for i=1,12 do if M.pid()>0 and M.api('/version')~=''and M.read(M.R..'/service-ready')=='1\n' then return end;M.run('sleep 1')end;fail('service_start_failed')end
end
local function guard()if (M.memory().MemAvailable or 0)<M.limits().protect_mb*1024 then fail('memory_protected')end end
local function current()return M.load(M.C..'/configs/config.json')end
local function checked_save(cfg)
 local policy_before=M.read(M.C..'/configs/policy.tsv');local policy_next=cfg._subscription_policy
 dofile(M.C..'/ax5/config-normalize.lua').normalize(cfg)
 M.save(M.R..'/candidate.json',cfg)
 local old=M.read(M.C..'/configs/config.json');local running=M.pid()>0
 if old==M.read(M.R..'/candidate.json')then return end
 local kind=M.state().core_kind
 if running then assert(M.run('lua '..M.C..'/ax5/state.lua save-selection'),'当前节点选择保存失败')end
 if cfg._native_meta then local ready=M.run('timeout -t 60 '..M.C..'/ax5/native-resources.sh '..M.R..'/candidate.json > '..M.R..'/geodata-check.log 2>&1');assert(ready,M.read(M.R..'/geodata-check.log',2048):gsub('%s+$','')~=''and M.read(M.R..'/geodata-check.log',2048):gsub('%s+$','')or'模板 Geo 数据库准备失败，当前配置保留')end
 local paused=kind=='meta'and running
 if paused then service('stop')end
 local command
 if kind=='meta'then
  local A=dofile(M.C..'/ax5/mihomo.lua');M.write(M.R..'/candidate.yaml',M.encode(A.build(cfg)):gsub('\\/','/'))
  command=M.C..'/ax5/check-binary.sh meta '..M.R..'/CrashCore -t -d '..M.R..' -f '..M.R..'/candidate.yaml'
 else command='GOMEMLIMIT=12MiB GOGC=25 '..M.R..'/CrashCore check -D '..M.R..' -c '..M.R..'/candidate.json'end
 collectgarbage('collect')
 M.write(M.R..'/check-context', 'pid='..M.pid()..' available_kb='..(M.memory().MemAvailable or 0)..' lua_kb='..collectgarbage('count')..'\n')
 local ok=M.run(command..' > '..M.R..'/check.log 2>&1')
 if not ok then if paused then pcall(service,'start')end;fail('configuration_check_failed_previous_kept')end
 if running and not paused then service('stop')end
 local ok,err=pcall(function()
  cfg._subscription_policy=nil;M.save(M.R..'/candidate.json',cfg)
  if policy_next then M.write(M.C..'/configs/policy.tsv',policy_next)end
  M.write(M.C..'/configs/config.json.new',M.read(M.R..'/candidate.json'));assert(os.rename(M.C..'/configs/config.json.new',M.C..'/configs/config.json'))
  -- Publication consumes the candidate. Release native rule tables and upload
  -- copies before launching Mihomo or waiting for the independent cloud backup.
  for k in pairs(cfg)do cfg[k]=nil end
  pcall(M.json.encode_keep_buffer,false);collectgarbage('collect')
  for _,name in ipairs({'upload-profile','upload-bounds','subscription.raw','subscription.nodes.raw','candidate.json','candidate.yaml'})do os.remove(M.R..'/'..name)end
  M.state();collectgarbage('collect') -- create the small index while the core is paused
  if running then service('start')end
 end)
 if not ok then
  M.write(M.C..'/configs/policy.tsv',policy_before);M.write(M.C..'/configs/config.json',old);if running then pcall(service,'start')end;fail('start_failed_previous_restored')
 end
end
local function fetched(url,file)
 if #url>2048 or not url:match('^https?://')or url:find('[%s\r\n]')then fail('invalid_subscription_url')end
 if file==M.R..'/subscription.raw'and M.run('test -x '..M.C..'/ax5/direct-download.sh')then
  M.write(M.R..'/subscription.progress','正在从原订阅地址兼容下载（不调用转换接口）\n')
  local ua='curl/'..(M.exec('curl --version'):match('curl%s+([^%s]+)')or'7')
  if M.run(M.C..'/ax5/direct-download.sh '..M.quote(file)..' '..M.quote(url)..' '..M.quote(ua))then
   M.write(M.R..'/subscription-tool.log',M.read(M.R..'/subscription-tool.log')..os.date('%Y-%m-%d %H:%M:%S')..' 面板兼容直连下载成功（未调用转换接口）\n');return
  end
 end
 local base='curl -4 -fsSL --connect-timeout 8 --max-time 25 --max-filesize 262144 '
 local proxy=M.pid()>0 and '--proxy http://127.0.0.1:7890 --noproxy "" 'or'--noproxy "*" '
 if not M.run(base..proxy..M.quote(url)..' -o '..M.quote(file))then
  if not M.run(base..'--noproxy "*" '..M.quote(url)..' -o '..M.quote(file))then fail('subscription_download_failed')end
 end
 if #M.read(file)>262144 or #M.read(file)<10 then fail('empty_subscription')end
end
local function upload(kind)
 if M.read(M.R..'/upload-id-'..kind)~=id then fail('invalid_upload')end
 return M.read(M.R..'/upload-'..kind,kind=='profile'and 1572864 or 262144)
end
local function record_subscription(parser)
 local info=M.load(M.R..'/subscription-attempt.json');if info.id~=id then return end
 local source=M.read(M.R..'/upload-source',8192);info.ua_override_b64=source:match('\nua=([A-Za-z0-9+/=]*)')or'';info.exclude_b64=source:match('\nexclude=([A-Za-z0-9+/=]*)')or'';local mode=source:match('\nexclude_mode=([A-Za-z0-9+/=]*)')or'';info.exclude_mode=mode=='YXV0bw=='and'auto'or mode=='cmVnZXg='and'regex'or'keyword';info.warnings=current()._subscription_warnings;info.id=nil;info.parser=parser;info.applied_at=os.time();info.core_kind=M.state().core_kind
 info.config_id=M.exec('md5sum '..M.quote(M.C..'/configs/config.json')..' 2>/dev/null'):match('^(%x+)')
 M.save(M.C..'/configs/subscription-state.json',info)
end
local function execute()
 local a=req.action
 if a=='restorego'then
  require('nixio').exec('/bin/sh',M.C..'/ax5/recovery-dispatch.sh','ax5',id,args[2]);fail('恢复执行器未能调度')
 elseif a=='advanced'then os.remove(M.R..'/dashboard-error');local advanced_kind=M.read(M.C..'/cache/core.env'):match('KIND=([^%s]+)')or'singbox';if not M.run('sh '..M.C..'/ax5/dashboard-install.sh '..M.C..' '..advanced_kind..' >> '..M.R..'/worker.log 2>&1')then local reason=M.read(M.R..'/dashboard-error'):gsub('%s+$','');fail(reason~=''and reason or'高级面板下载或校验失败，请查看运行日志')end;phase('done','高级面板已准备',false)
 elseif a=='cnbypass'then
  if args[2]=='1'then guard()end;dofile(M.C..'/ax5/cn-bypass.lua').apply(M,args[2]);phase('done','国内 IP 绕过设置已保存；只影响新连接',false)
 elseif a=='transport'then
  local message=dofile(M.C..'/ax5/transport-mode.lua').apply(args[2],service,phase);phase('done',message,false)
 elseif a=='proxymode'then
  phase('working','正在切换流量接管',true);dofile(M.C..'/ax5/traffic-mode.lua').apply(args[2]);phase('done','流量模式已生效',false)
 elseif a=='start'or a=='stop'or a=='restart'then service(a);phase('done','service_operation_complete',false)
 elseif a=='clear'then M.write(M.R..'/operations.log','');M.write(M.R..'/core.log','');M.write(M.R..'/service.log','');M.write(M.R..'/subscription-tool.log','');phase('done','logs_cleared',false)
 elseif a=='cleanup'then M.cleanup(true);phase('done','memory_cleaned',false)
 elseif a=='memcfg'then
  guard();local w,p,c=(args[2]or''):match('^w(%d+)p(%d+)c(%d+)$');w,p,c=tonumber(w),tonumber(p),tonumber(c)
  if not w or not p or not c or p<12 or w<=p or w>64 or(c~=0 and(c<w or c>96))then fail('memory_settings_invalid')end
  M.save(M.C..'/configs/memory.json',{warning_mb=w,protect_mb=p,cleanup_mb=c});phase('done','memory_settings_saved',false)
 elseif a=='guard'then
  local mode=args[2];if mode~='procd'and mode~='conservative'then fail('invalid_guard_mode')end
  local path='/data/ShellCrash-tool/configs/ShellCrash.cfg';local old=M.read(path);local on=mode=='conservative'and'ON'or'OFF'
  local was_running=M.pid()>0
  if not M.run("CRASHDIR=/data/ShellCrash-tool; export CRASHDIR; . $CRASHDIR/libs/set_config.sh; setconfig start_old "..on)then M.write(path,old);fail('guard_save_failed')end
  if was_running then
   local ok=pcall(service,'restart');if not ok then M.write(path,old);pcall(service,'restart');fail('guard_apply_failed_previous_restored')end
  end
  phase('done','guard_saved',false)
 elseif a=='fetch'then
  guard();M.write(M.R..'/subscription-tool.log','');os.remove(M.R..'/subscription.error');os.remove(M.R..'/subscription.endpoint');os.remove(M.R..'/subscription.progress');phase('fetching','downloading_subscription',true);local url=upload('source'):match('^[^\r\n]+')or'';local mode=args[2]=='convert'and'convert'or'direct';local fetcher=args[2]=='panel'and'panel'or'shellcrash';os.remove(M.R..'/subscription-fetch.info');local policy=args[3]or's0a1';if not policy:match('^s[0-8]a[01]$')then fail('invalid_arguments')end;if args[2]=='panel'then fetched(url,M.R..'/subscription.raw') elseif not M.run(M.C..'/ax5/subscription-tool.sh ax5 '..mode..' '..policy)then if mode=='direct'then fetcher='panel';local fallback_ok,fallback_err=pcall(fetched,url,M.R..'/subscription.raw');if not fallback_ok then local reason=M.read(M.R..'/subscription.error'):match('^(subscription_[%w_]+)');fail(reason or fallback_err)end else local reason=M.read(M.R..'/subscription.error'):match('^(subscription_[%w_]+)');fail(reason or 'subscription_download_failed')end end;local info={id=id,method=args[2]=='panel'and'panel'or mode,fetcher=fetcher,converter_policy=policy};if fetcher=='shellcrash'then for k,v in M.read(M.R..'/subscription-fetch.info',4096):gmatch('([%w_]+)=([^\n]*)')do info[k]=v end end;M.save(M.R..'/subscription-attempt.json',info);phase('downloaded','subscription_downloaded',false)
 elseif a=='apply'and args[2]=='native'then
  guard();phase('working','正在保留 ShellCrash 模板策略组与规则',true)
  local base=M.json.decode(upload('profile'));local cfg=current()
  if M.state().core_kind=='meta'then cfg=dofile(M.C..'/ax5/native-profile.lua').import(cfg,base)
  else cfg=dofile(M.C..'/ax5/native-profile.lua').import_singbox(cfg,base)end
  base=nil;collectgarbage('collect');checked_save(cfg)
  M.write(M.C..'/configs/subscription.new',(upload('source'):match('^[^\r\n]+')or''));assert(os.rename(M.C..'/configs/subscription.new',M.C..'/configs/subscription'))
  record_subscription('native');os.remove(M.C..'/configs/needs-subscription');if M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then phase('done','subscription_updated',false)else phase('done','configuration_saved_backup_pending',false)end
 elseif a=='apply'then
  guard();local out=M.json.decode(upload('bounds'));if type(out)~='table'or #out<3 or #out>540 then fail('invalid_upload')end
  local count=0;for _,n in ipairs(out)do
   if type(n.tag)~='string'or type(n.type)~='string'then fail('invalid_upload')end
   if n.type~='selector'and n.type~='urltest'and n.type~='block'then n.routing_mark=21315 end
   if n.server then count=count+1 end
  end
  if count==0 then fail('empty_subscription')end
  out[#out+1]={type='selector',tag='DIRECT',outbounds={'direct'},default='direct'}
  out[#out+1]={type='selector',tag='GLOBAL',outbounds={'proxy-main'},default='proxy-main'}
  local cfg=current();cfg._native_meta=nil;cfg._template_kind=nil;local present={};for _,o in ipairs(out)do present[o.tag]=true end;for _,o in ipairs(cfg.outbounds or{})do if o.tag:match('^分流/')and not present[o.tag]then out[#out+1]=o end end;local N=dofile(M.C..'/ax5/node-identity.lua');N.preserve(cfg.outbounds,out);dofile(M.C..'/ax5/group-mode.lua').preserve(cfg.outbounds,out);cfg.outbounds=out;cfg._subscription_warnings={};for _,o in ipairs(out)do if o._subscription_reset and o.tag:match('^分流/')then cfg._subscription_warnings[#cfg._subscription_warnings+1]=o.tag..' 的固定选择已排除，已重置为默认代理'end;o._subscription_reset=nil end;dofile(M.C..'/ax5/group-mode.lua').layout(cfg);local P=dofile(M.C..'/ax5/policy.lua');cfg._subscription_policy=P.reconcile(cfg,M.read(M.C..'/configs/policy.tsv'));P.groups(cfg,P.parse(cfg._subscription_policy,cfg));N.validate_targets(cfg);checked_save(cfg)
  M.write(M.C..'/configs/subscription.new',(upload('source'):match('^[^\r\n]+')or''));assert(os.rename(M.C..'/configs/subscription.new',M.C..'/configs/subscription'))
  record_subscription('panel');os.remove(M.C..'/configs/needs-subscription');if M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then phase('done','subscription_updated',false)else phase('done','configuration_saved_backup_pending',false)end
 elseif a=='grouplayout'then guard();checked_save(dofile(M.C..'/ax5/group-mode.lua').layout(current()));M.write(M.C..'/configs/group-layout','1\n');phase('done','手动与自动策略组已生效',false)
 elseif a=='groupmode'then
  guard();assert(not current()._template_kind,'完整模板的组模式由 ShellCrash 模板定义；可在两个面板选择已有组成员')
  local text=upload('group');local tag,mode=text:match('^([^\t\n]+)\t(%a+)\n$');assert(tag and #tag<=256,'策略组参数无效')
  local cfg=dofile(M.C..'/ax5/group-mode.lua').apply(current(),tag,mode);checked_save(cfg)
  phase('done','策略组选择模式已生效',false)
 elseif a=='policy'then
  guard();phase('working','正在校验域名分流',true)
  local P=dofile(M.C..'/ax5/policy.lua');local cfg=current();local text=upload('policy');local before=M.read(M.C..'/configs/policy.tsv')
  local rows=P.parse(text,cfg);local old=P.parse(before,cfg)
  P.groups(cfg,rows);text=P.text(rows)
  M.write(M.C..'/configs/policy.tsv',text)
  local ok,err=pcall(checked_save,P.apply(cfg,rows,old));if not ok then M.write(M.C..'/configs/policy.tsv',before);fail(err)end
  if M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then phase('done','域名分流已保存并生效',false)else phase('done','configuration_saved_backup_pending',false)end
 elseif a=='dns'then
  guard();local mode=args[2]=='real'and'redir_host'or args[2]=='mix'and'mix';if not mode then fail('invalid_upload')end
  local filter=upload('filter');if #filter>16000 then fail('invalid_filter_previous_kept')end
  if not M.run('awk -f '..M.C..'/ax5/filter_compile.awk '..M.R..'/upload-filter > '..M.R..'/filter.json')then fail('invalid_filter_previous_kept')end
  if M.read(M.C..'/configs/fake_ip_filter.list')==filter and M.read(M.C..'/configs/dns-mode'):match('^%s*(%S+)')==mode then
   phase('done','DNS 设置未变化，无需重启',false);return
  end
  local f=M.load(M.R..'/filter.json');local cfg=current();local dns=cfg.dns;local servers={}
  for _,s in ipairs(dns.servers)do if s.type~='fakeip'then servers[#servers+1]=s end end
  local rules={};for _,r in ipairs(dns.rules)do
   if r.ip_accept_any or r.rule_set or (r.domain and r.domain[1]=='localhost')then rules[#rules+1]=r end
  end
  if mode=='mix'then
   servers[#servers+1]={type='fakeip',tag='dns-fake',inet4_range='198.18.0.0/15'};f.server='dns-proxy';rules[#rules+1]=f
   rules[#rules+1]={query_type={'A'},server='dns-fake',rewrite_ttl=1}
  end
  rules[#rules+1]={query_type={'AAAA'},action='reject'};dns.servers=servers;dns.rules=rules
  local oldfilter=M.read(M.C..'/configs/fake_ip_filter.list');local oldmode=M.read(M.C..'/configs/dns-mode')
  M.write(M.C..'/configs/fake_ip_filter.list',filter);M.write(M.C..'/configs/dns-mode',mode)
  local ok,err=pcall(checked_save,cfg)
  if not ok then M.write(M.C..'/configs/fake_ip_filter.list',oldfilter);M.write(M.C..'/configs/dns-mode',oldmode);if M.pid()>0 then pcall(service,'restart')end;fail(err)end
  os.remove(M.C..'/configs/needs-subscription');if M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then phase('done','dns_updated',false)else phase('done','configuration_saved_backup_pending',false)end
 elseif a=='domainupdate'then
  guard();phase('working','database_updating',true);local result=dofile(M.C..'/ax5/database.lua').update(M,service);phase('done',result,false)
 elseif a=='rules'then
  guard();phase('fetching','downloading_rules',true);fetched('https://ispip.clang.cn/all_cn.txt',M.R..'/rules.raw')
  if not M.run('awk -f '..M.C..'/ax5/rules_validate.awk '..M.R..'/rules.raw > '..M.R..'/rules.new')then fail('rules_invalid_previous_kept')end
  local ips={};for line in M.read(M.R..'/rules.new'):gmatch('[^\n]+')do ips[#ips+1]=line end
  if #ips<1000 or #ips>10000 then fail('rules_invalid_previous_kept')end
  local cfg=current()
  if cfg._native_meta and M.state().core_kind=='meta'and M.pid()>0 then
   cfg=nil;collectgarbage('collect')
   if not dofile(M.C..'/ax5/rules-update.lua').apply(M,table.concat(ips,'\n')..'\n',#ips)then phase('done','国内 IP 表未变化，无需重启',false);return end
  else
   local changed=0;for _,r in ipairs(cfg.route.rules)do if r.ip_cidr and #r.ip_cidr>1000 then r.ip_cidr=ips;changed=changed+1 end end
   if changed~=1 then fail('configuration_template_missing')end
   checked_save(cfg);M.write(M.C..'/configs/cn_ip.txt',table.concat(ips,'\n')..'\n')
  end
  M.write(M.C..'/configs/rules-count',tostring(#ips)..'\n');M.write(M.C..'/configs/rules-date',os.date('%Y-%m-%d %H:%M:%S'));os.remove(M.C..'/configs/needs-subscription');if M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then phase('done','国内 IP 兜底表已更新并加载',false)else phase('done','规则已加载，远端备份待同步',false)end
 elseif a=='coreupdate'then
  guard();local kind=args[2];if kind~='singbox'and kind~='meta'then fail('invalid_core')end
  phase('working','downloading_core_update',true)
  local ok=M.run('SC_CORE_JOB=1 '..M.C..'/ax5/core-fetch.sh '..kind..' >> '..M.R..'/service.log 2>&1')
  if not ok then fail('core_update_failed_previous_kept')end
  phase('done','core_updated',false)
 elseif a=='toolcheck'or a=='toolupdate'then
  guard();phase('working',a=='toolcheck'and'checking_tool_release'or'updating_tool_release',true)
  if not M.run('SC_TOOL_JOB=1 '..M.C..'/ax5/tool-update.sh ax5 '..(a=='toolcheck'and'check'or'update')..' >> '..M.R..'/service.log 2>&1')then fail('tool_update_rejected_previous_kept')end
  phase('done',a=='toolcheck'and'tool_checked'or'tool_updated',false)
 elseif a=='mirrortest'then
  local raw=upload('mirror');if #raw>4096 then fail('mirror_invalid')end
  phase('working','正在测试候选 WebDAV 设置',true)
  if not M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote.sh"; . "$C/ax5/remote-settings.sh"; remote_settings_test "$D/upload-mirror"\' > '..M.R..'/remote-test.log 2>&1')then
   M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote-settings.sh"; remote_settings_error "$D/remote-test.log"\' > '..M.R..'/remote-test.error')
   fail(M.read(M.R..'/remote-test.error',512):gsub('%s+$',''))
  end
  phase('done','WebDAV 测试通过，尚未保存',false)
 elseif a=='mirrorsave'then
  local raw=upload('mirror');if #raw>4096 then fail('mirror_invalid')end
  if not M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote.sh"; . "$C/ax5/remote-settings.sh"; remote_settings_commit "$D/upload-mirror"\' > '..M.R..'/remote-save.error 2>&1')then fail(M.read(M.R..'/remote-save.error',512):gsub('%s+$',''))end
  M.save(M.R..'/mirror-check.json',{available=false});phase('done','mirror_saved',false)
 elseif a=='mirrorverify'then
  phase('working','正在验证 WebDAV 读写',true)
  if not M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote.sh"; remote_verify\' >> '..M.R..'/service.log 2>&1')then fail('WebDAV 验证失败，请检查地址、账号密码与读写权限')end
  phase('done','远程仓库验证通过',false)
 elseif a=='restorecheck'then
  local raw=upload('restore');if #raw>200 then fail('恢复检查请求过长')end
  phase('working','正在核对备份组件，当前代理保持运行',true)
  require('nixio').exec('/bin/sh',M.C..'/ax5/recovery-inspect-job.sh','ax5',id);fail('恢复预检调度失败')
 elseif a=='baselinecreate'then
  local mode=args[2];if mode~='create'and mode~='replace'then fail('需要明确选择创建或替换基础版本')end
  phase('working','正在生成并校验独立基础版本，当前代理保持运行',true)
  if not M.run(M.C..'/ax5/backup-baseline-run.sh ax5 '..mode..' > '..M.R..'/baseline-result.log 2>&1')then fail('基础版本未更新，请查看日志；原基础版本保留')end
  phase('done','基础版本已独立保存并校验',false)
 elseif a=='backuplocal'or a=='backupremote'then
  phase('working','正在备份应用',true)
  os.remove(M.R..'/backup-error')
  if not M.run(M.C..'/ax5/backup-app.sh '..(a=='backupremote'and'remote'or'local')..' >> '..M.R..'/service.log 2>&1')then local reason=M.read(M.R..'/backup-error'):gsub('%s+$','');fail(reason~=''and reason or'应用备份失败，请查看日志；当前服务保持运行')end
  phase('done','应用备份完成',false)
 elseif a=='mirrorsync'then
  guard();phase('working','mirror_syncing',true)
  if not M.run(M.C..'/ax5/mirror-sync.sh >> '..M.R..'/service.log 2>&1')then M.write(M.C..'/configs/mirror-pending','Synchronization pending\n');fail('mirror_sync_failed')end
  phase('done','mirror_synced',false)
 elseif a=='corecheck'then
  local ok=M.run(M.C..'/ax5/verify-core.sh > '..M.R..'/check.log 2>&1')
  if not ok then fail('core_current_invalid')end
  local s=M.state();local kind=args[2]or s.core_kind;if kind~='meta'and kind~='singbox'then fail('invalid_core')end;M.run(M.C..'/ax5/mirror-status.sh '..kind..' 2>> '..M.R..'/service.log');local latest=M.exec(M.C..'/ax5/core-source.sh version '..kind..' 2>> '..M.R..'/service.log'):match('([v%d][%w.+_-]*)%s*$')
  local job={kind=kind,available=latest~=nil,fits=true,fixed=false,version=latest or s.core_version,git_blob=(latest and latest:gsub('^v','')~=s.core_version:gsub('^v',''))and('source_'..latest)or M.read(M.C..'/cache/core.sha256'):match('^(%x+)'),size=tonumber(M.exec('wc -c < '..M.C..'/cache/core-armv7.tar.gz'))or 0,checked=os.time()}
  M.save(M.R..'/core-check.json',job);phase('done','core_checked',false)
 else fail('unsupported_action')end
end
local ok,err=pcall(execute)
if not ok then phase('error',tostring(err),false);M.write(M.R..'/last-job-error',tostring(err))end
if req.action=='mirrorsave'or req.action=='mirrortest'then os.remove(M.R..'/upload-mirror');os.remove(M.R..'/upload-id-mirror')end
if req.action=='apply'or req.action=='dns'or req.action=='policy'or req.action=='groupmode'then
 for _,kind in ipairs({'source','bounds','profile','filter','policy','group','mirror'})do os.remove(M.R..'/upload-'..kind);os.remove(M.R..'/upload-id-'..kind)end
 os.remove(M.R..'/subscription.raw');os.remove(M.R..'/subscription.nodes.raw')
end
os.remove(M.R..'/operation.lock/owner')
os.remove(M.R..'/operation.lock')
if ok and(req.action=='apply'or req.action=='start'or req.action=='restart')then M.run('sh '..M.C..'/ax5/subscription-quota.sh ax5 auto >/dev/null 2>&1')end
