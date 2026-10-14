local M={C='/data/ShellCrash',R='/tmp/ShellCrash'}
M.json=require('cjson')
function M.read(p,max) local f=io.open(p,'rb');if not f then return '' end;local s=f:read(max or '*a') or '';f:close();return s end
function M.write(p,s) local f=assert(io.open(p,'wb'));assert(f:write(s));f:close() end
function M.load(p,default) local ok,v=pcall(M.json.decode,M.read(p));if ok then return v end;return default or {} end
function M.encode(v)
 local s=M.json.encode(v)
 for _,key in ipairs({'domain','domain_suffix','domain_regex','query_type','rule_set','rules','servers','ip_cidr','outbounds','alpn','path','connections','rows'})do s=s:gsub('"'..key..'":{}','"'..key..'":[]')end
 return s
end
function M.save(p,v) M.write(p..'.new',M.encode(v));assert(os.rename(p..'.new',p)) end
function M.quote(s) return "'"..tostring(s):gsub("'","'\\''").."'" end
function M.exec(s) local p=io.popen(s);local out=p:read('*a');p:close();return out end
function M.run(s) return os.execute(s)==0 end
function M.b64(s) local nixio=require('nixio');return nixio.bin.b64encode(s or '') end
function M.pid() local n=tonumber(M.read(M.R..'/core.pid'));if n and M.read('/proc/'..n..'/cmdline'):find('/tmp/ShellCrash/CrashCore',1,true) then return n end;return 0 end
-- Linux exposes process start times in USER_HZ (100), independent of wall-clock changes.
function M.core_uptime(pid)
 if not pid or pid<=0 then return nil end
 local now=tonumber(M.read('/proc/uptime'):match('^(%S+)'))
 local rest=M.read('/proc/'..pid..'/stat'):match('^%d+ %(.+%) (.+)$')
 if not now or not rest then return nil end
 local fields={};for v in rest:gmatch('%S+')do fields[#fields+1]=v end
 local ticks=tonumber(fields[20])
 if not ticks or ticks<0 or ticks/100>now then return nil end
 return math.floor(now-ticks/100)
end
function M.memory() local d={};for k,v in M.read('/proc/meminfo'):gmatch('([%w_]+):%s+(%d+)')do d[k]=tonumber(v) end;return d end
function M.limits() local d=M.load(M.C..'/configs/memory.json');local w,p,c=tonumber(d.warning_mb),tonumber(d.protect_mb),tonumber(d.cleanup_mb);if not w or not p or not c or p<12 or w<=p or w>64 or (c~=0 and (c<w or c>96)) then return {warning_mb=20,protect_mb=14,cleanup_mb=20} end;return d end
function M.request(path,method,body)
 local header=M.C..'/configs/api-header'
 local cmd='curl --noproxy "*" -fsS --connect-timeout 2 --max-time 10 -H '..M.quote(M.read(header):gsub('%s+$',''))..' '
 if method and method~='GET' then cmd=cmd..'-X '..M.quote(method)..' -H "Content-Type: application/json" --data-binary '..M.quote(body or '')..' ' end
 local raw=M.exec(cmd..'-w "\\n%{http_code}" '..M.quote('http://127.0.0.1:9999'..path)..' 2>/dev/null')
 local content,status=raw:match('^(.*)\n(%d%d%d)$');return content or'',tonumber(status)or 0
end
function M.api(path,method,body) local raw=M.request(path,method,body);return raw end
function M.lock(name,ttl)
 local p=M.R..'/'..name;local stamp=p..'.time'
 if M.run('mkdir '..M.quote(p)..' 2>/dev/null')then M.write(stamp,tostring(os.time()));return true end
 local t=tonumber(M.read(stamp));if not t then local a=require('nixio.fs').stat(p);t=a and a.mtime end
 if t and os.time()-t>ttl then
  if M.run('rmdir '..M.quote(p)..' 2>/dev/null')then os.remove(stamp);return M.lock(name,ttl)end
 end
 return false
end
function M.zerotier()
 local cli='/opt/bin/zerotier-cli';local out={checked=os.time(),installed=M.read(cli,4)~=''}
 if not out.installed then return out end
 local info=M.exec('timeout -t 3 '..cli..' info 2>/dev/null')
 out.node_id,out.version,out.status=info:match('200 info (%x+) ([%d.]+) ([A-Z_]+)')
 out.status=out.status or 'UNAVAILABLE';out.networks={}
 local nets=M.exec('timeout -t 3 '..cli..' listnetworks 2>/dev/null')
 for line in nets:gmatch('[^\n]+')do
  local id,rest=line:match('^200 listnetworks (%x+) (.+)$')
  if id and #id==16 then
   local name,mac,status,kind,device,ips=rest:match('^(.-) ([%x:]+) ([A-Z_]+) ([A-Z]+) ([%w_-]+) (.+)$')
   if status then out.networks[#out.networks+1]={id=id,name=name,status=status,device=device,ips=ips}end
  end
 end
 M.save(M.R..'/zerotier.json',out)
 local text=os.date('%Y-%m-%d %H:%M:%S')..' node='..(out.node_id or '-')..' status='..out.status
 for _,n in ipairs(out.networks)do text=text..' | '..n.id..' '..n.status..' '..n.ips end
 local previous=M.read(M.R..'/zerotier-diagnostic',8192);local lines={};for line in previous:gmatch('[^\n]+')do lines[#lines+1]=line end
 while #lines>=30 do table.remove(lines,1)end;lines[#lines+1]=text
 M.write(M.R..'/zerotier-diagnostic',table.concat(lines,'\n')..'\n');return out
end
function M.state()
 local mem=M.memory();local pid=M.pid();local stat=M.read('/proc/'..pid..'/status');local limits=M.limits();local avail=mem.MemAvailable or mem.MemFree or 0
 local job=M.load(M.R..'/job.json',{phase='done',active=false,message_b64=M.b64('service_operation_complete')})
 if job.active then local t=tonumber(M.read(M.R..'/operation.lock.time'));if t and os.time()-t>900 then job.active=false;job.phase='error';job.message_b64=M.b64('operation_timed_out');M.save(M.R..'/job.json',job)end end
 local fs=require('nixio.fs');local statcfg=fs.stat(M.C..'/configs/config.json')or{};local index=M.load(M.R..'/config-index.json')
 local cn_policy=M.read(M.C..'/configs/policy.tsv');local cn_dns=M.read(M.C..'/configs/dns-mode'):gsub('%s+$','')
 if index.mtime~=statcfg.mtime or index.bytes~=statcfg.size or index.native_mihomo==nil or not index.cn_warning or not index.cn_eligible or index.cn_policy~=cn_policy or index.cn_dns~=cn_dns then
  local cfg=M.load(M.C..'/configs/config.json');local count=0;for _,r in ipairs((cfg.route or{}).rules or{})do count=count+#(r.ip_cidr or{})end
  local native=cfg._native_meta;index={native_mihomo=native~=nil,mtime=statcfg.mtime,bytes=statcfg.size,ip_count=count,template_kind=cfg._template_kind,template_rules=native and #native.rules or cfg._template_kind and #(cfg.route.rules or{})or 0,template_groups=native and #native['proxy-groups']or 0,main_group=native and native['proxy-groups'][1]and native['proxy-groups'][1].name}
  local CB=dofile(M.C..'/ax5/cn-bypass.lua');index.cn_eligible=CB.check(cfg,cn_policy,cn_dns);index.cn_warning=CB.warning(cfg,cn_policy,cn_dns);index.cn_policy=cn_policy;index.cn_dns=cn_dns
  pcall(M.save,M.R..'/config-index.json',index)
 end
 local count=tonumber(M.read(M.C..'/configs/rules-count'))or index.ip_count or 0
 local sock=M.read('/proc/net/sockstat');local pages=tonumber(sock:match('TCP:[^\n]* mem (%d+)')) or 0
 local incidents=M.read(M.R..'/incidents');local recoveries=0;for _ in incidents:gmatch('\n') do recoveries=recoveries+1 end
 local coreenv=M.read(M.C..'/cache/core.env');local kind=coreenv:match('KIND=([^%s]+)')or'singbox';local ver=coreenv:match('VERSION=([^%s]+)')or'1.12.13'
 local s={running=pid>0,pid=pid,core_uptime_seconds=M.core_uptime(pid),available_kb=avail,free_kb=mem.MemFree or 0,rss_kb=tonumber(stat:match('VmRSS:%s+(%d+)')) or 0,shmem_kb=mem.Shmem or 0,slab_kb=mem.Slab or 0,tcp_kb=pages*4,conntrack=tonumber(M.read('/proc/sys/net/netfilter/nf_conntrack_count')) or 0,pressure=avail<limits.protect_mb*1024 and 'protect' or avail<limits.warning_mb*1024 and 'warning' or 'normal',memory_limits=limits,dns_mode=M.read(M.C..'/configs/dns-mode'):gsub('%s+$',''),url_b64=M.b64(M.read(M.C..'/configs/subscription'):gsub('%s+$','')),core_kind=kind,core_version=ver,core_blob=M.read(M.C..'/cache/core.sha256'):match('^(%x+)'),rules_count=count,rules_date_b64=M.b64(M.read(M.C..'/configs/rules-date')),recoveries=recoveries,cleanup=M.load(M.R..'/cleanup.json')}
 s.cn_bypass=dofile(M.C..'/ax5/cn-bypass.lua').state(M,index)
 if s.cn_bypass.enabled and s.running and not fs.access(M.R..'/operation.lock') then local raw,code=M.request('/configs');local ok,d=pcall(M.json.decode,raw);if code==200 and ok then local mode=tostring(d.mode):lower();local applied=M.read(M.R..'/cn-checked'):gsub('%s+$','');if applied~=mode..':'..index.cn_eligible then M.run('SC_CN_FLOW_MODE='..M.quote(mode)..' '..M.C..'/ax5/cn-bypass.sh apply');s.cn_bypass=dofile(M.C..'/ax5/cn-bypass.lua').state(M,index)end end end
 s.transport=dofile(M.C..'/ax5/transport-mode.lua').state()
 s.traffic_mode=M.read(M.R..'/traffic-mode'):gsub('%s+$','');if not({rule=true,direct=true,global=true})[s.traffic_mode]then s.traffic_mode='rule'end
 s.quota_revision_b64=M.b64(M.read(M.R..'/subscription-quota.revision',64));s.subscription=M.load(M.C..'/configs/subscription-state.json');s.domestic_hot_reload=kind=='meta'and index.native_mihomo==true;s.template_kind=index.template_kind;s.template_rules=index.template_rules;s.template_groups=index.template_groups;s.main_group=index.main_group
 local toolcfg='\n'..M.read('/data/ShellCrash-tool/configs/ShellCrash.cfg')
 s.autostart=not fs.stat('/data/ShellCrash-tool/.dis_startup') and fs.stat('/etc/rc.d/S99shellcrash')~=nil
 s.guard_mode=toolcfg:match('\nstart_old=ON[\r\n]') and 'conservative' or 'procd'
 s.guard_runtime=M.read(M.R..'/guard-mode'):gsub('%s+$','');s.guard_active=pid>0
 s.start_source=M.read(M.R..'/control-source'):gsub('%s+$','')
 s.guard_owner=s.guard_runtime=='conservative' and 'panel' or 'procd'
 s.domain_database=M.load(M.C..'/configs/domain-'..kind..'.json');s.domain_check=M.load(M.R..'/domain-check.json');s.domain_file='cn.'..(kind=='meta'and'mrs'or'srs')
 s.needs_subscription=M.read(M.C..'/configs/needs-subscription')~='';s.tool_version=M.read('/data/ShellCrash-tool/version',64):gsub('%s+$','');s.tool_check=M.load(M.R..'/tool-check.json')
 s.mirror_check=M.load(M.R..'/mirror-check.json');s.core_check=M.load(M.R..'/core-check.json');s.local_archive=M.read(M.C..'/cache/core-armv7.tar.gz',4)~=''
 s.mirror_base_b64=M.b64(M.read(M.C..'/configs/mirror.conf'):match('base=([^\n]*)')or'');s.mirror_target_b64=M.b64(M.read(M.C..'/configs/mirror.conf'):match('target=([^\n]*)')or'')
 s.remote_enabled=M.read(M.C..'/configs/mirror.conf'):match('enabled=1\n')~=nil
 s.remote_transport=M.read(M.C..'/configs/mirror.conf'):match('transport=([^\n]*)')or'ssh'
 s.webdav_user_b64=M.b64(M.read(M.C..'/configs/webdav.user',1024));s.webdav_password_set=M.read(M.C..'/configs/webdav.auth',4)~=''
 s.remote_checked=tonumber(M.read(M.C..'/configs/remote.checked'))or 0
 s.remote_application_b64=M.b64(M.read(M.R..'/remote-application.json',2048));s.remote_config_b64=M.b64(M.read(M.R..'/remote-config.json',2048))
 s.remote_verified=M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote.sh"; remote_ready\' 2>/dev/null')
 s.mirror_ready=M.read(M.C..'/configs/mirror-id',4)~='';s.core_sha=s.core_blob;s.mirror_pending=M.read(M.C..'/configs/mirror-pending',256):gsub('%s+$','')
 for k,v in pairs(job)do s[k]=v end
 return s
end
function M.trimlogs()
 local bytes,trimmed=0,0
 for _,name in ipairs({'core.log','service.log','worker.log'})do
  local p=M.R..'/'..name;local f=io.open(p,'rb');if f then local size=f:seek('end') or 0;f:close();if size>65536 then local f=io.open(p,'rb');f:seek('end',-32768);local data=f:read('*a');f:close();M.write(p,data);bytes=bytes+size-32768;trimmed=trimmed+1 end end
 end
 return bytes,trimmed
end
function M.cleanup(manual)
 local before=M.memory().MemAvailable or 0;local bytes,trimmed=M.trimlogs();local removed=0
 -- Clean only files created by this adapter, never the running binary or Fake IP DB.
 for _,name in ipairs({'candidate.json','check.log'})do
  local p=M.R..'/'..name;local f=io.open(p,'rb');if f then local n=f:seek('end') or 0;f:close();if os.remove(p)then bytes=bytes+n;removed=removed+1 end end
 end
 M.save(M.R..'/cleanup.json',{time=os.time(),manual=manual,removed=removed,trimmed=trimmed,file_bytes=bytes,before_kb=before,after_kb=M.memory().MemAvailable or 0})
end
return M
