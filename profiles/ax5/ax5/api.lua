local M=dofile('/data/ShellCrash/ax5/common.lua')
local H=require('luci.http');local D=require('luci.dispatcher')
local A={}
local function reply(v,code) H.status(code or 200);H.header('Cache-Control','no-store');H.prepare_content('application/json');H.write(M.encode(v))end
local function body()
 local n=tonumber(H.getenv('CONTENT_LENGTH')) or 0;if n>262144 then return nil end
 local raw=H.formvalue('payload');local ok,d=pcall(M.json.decode,raw or '');if ok and type(d)=='table' then return d end
end
local function csrf()
 return H.getenv('HTTP_X_SC_CSRF')==M.read(M.R..'/csrf'):gsub('%s+$','') and #M.read(M.R..'/csrf')>16
end
function A.panel()
 local base=D.build_url('web','shellcrash');local html=M.read(M.C..'/ui/index.html');html=html:gsub('@@BASE@@',base)
 H.header('Cache-Control','no-store');H.prepare_content('text/html');H.write(html)
end
function A.asset()
 local name=H.formvalue('name') or '';local allowed={['manager.js']=true,['js-yaml.min.js']=true,['health.js']=true,['sites.js']=true,['google.svg']=true,['tencent.svg']=true}
 if not allowed[name]then reply({error='not_found'},404);return end
 H.prepare_content(name:match('%.svg$')and'image/svg+xml'or'application/javascript');H.write(M.read(M.C..'/ui/'..name))
end
function A.read()
 local kind=H.formvalue('kind');H.header('Cache-Control','no-store')
 if kind=='auth' then
  if not M.run('mkdir -p '..M.R)then reply({error='runtime_missing'},500);return end
  if M.read(M.R..'/csrf')==''then M.run('umask 077; head -c 24 /dev/urandom | base64 > '..M.R..'/csrf')end
  reply({token_b64='',control_token=M.read(M.R..'/csrf'):gsub('%s+$','')});return
 elseif kind=='converters'then
  local T='/data/ShellCrash-tool';local list=M.read(T..'/configs/servers.list');if list==''then list=M.read(T..'/servers.list')end
  local entries={};for line in list:gmatch('[^\r\n]+')do
   local name,url=line:match('^[34]%d%d%s+(%S+)%s+(https?://%S+)');if name and #entries<8 then entries[#entries+1]={id=#entries+1,name=name,url=url}end
  end
  local templates={};for line in list:gmatch('[^\r\n]+')do local name,url=line:match('^5%d%d%s+(%S+)%s+(https?://%S+)');if name and #templates<100 then templates[#templates+1]={name=name,url=url}end end
  local defaults=dofile(M.C..'/ax5/subscription-defaults.lua').read(M.read(T..'/configs/ShellCrash.cfg'),list,M.read(T..'/version',64))
  reply({servers=entries,templates=templates,defaults=defaults});return
 elseif kind=='zerotier'then reply(M.zerotier());return
 elseif kind=='zerotierlog'then H.prepare_content('text/plain');H.write(M.read(M.R..'/zerotier-diagnostic',8192));return
 elseif kind=='inspect'then
  local d,err,status=dofile(M.C..'/ax5/inspect.lua').query(H.formvalue('view')or'',tonumber(H.formvalue('page')or'0'),H.formvalue('q')or'')
  reply(d or{error=err},status);return
 elseif kind=='backup'or kind=='corebackup'then
  local path=kind=='backup'and(M.R..'/application-backup.tar.gz')or(M.C..'/cache/core-armv7.tar.gz')
  local f=io.open(path,'rb');if not f then reply({error='backup_not_ready'},404);return end
  local size=f:seek('end');f:seek('set',0);H.header('Content-Length',tostring(size))
  local corehash=M.read(M.C..'/cache/core.sha256',128):gsub('%s+$','');local filename=kind=='backup'and'AX5-application-backup.tar.gz'or(corehash:match('^%x+$')and #corehash==64 and('core-'..corehash..'.tar.gz')or'AX5-core.tar.gz')
  H.prepare_content('application/gzip');H.header('Content-Disposition','attachment; filename="'..filename..'"')
  while true do local chunk=f:read(32768);if not chunk then break end;H.write(chunk)end;f:close();return
 elseif kind=='remoteconnection'then
  M.run('C='..M.C..' D='..M.R..' sh -c \'. "$C/ax5/remote.sh"; dav_status > "$D/remote-connection.out"\'');H.prepare_content('application/json');H.write(M.read(M.R..'/remote-connection.out',512));return
 elseif kind=='state'then reply(M.state());return end
 local paths={progress=M.R..'/subscription.progress',subscriptionlog=M.R..'/subscription-tool.log',endpoint=M.R..'/subscription.endpoint',policy=M.C..'/configs/policy.tsv',filter=M.C..'/configs/fake_ip_filter.list',subscriptionnodes=M.R..'/subscription.nodes.raw',subscription=M.R..'/subscription.raw',memory=M.R..'/memory.csv',incidents=M.R..'/incidents',logs=M.R..'/core.log'}
 if not paths[kind]then reply({error='not_found'},404);return end
 H.prepare_content('text/plain');local text=M.read(paths[kind],(kind=='subscription'or kind=='subscriptionnodes')and 1572864 or 262144)
 if kind=='logs'then
  local groups={{'操作记录','operations.log',32768},{'内核运行','core.log',32768},{'订阅获取','subscription-tool.log',16384},{'服务启动与备份','service.log',16384},{'最近后台操作','worker.log',8192},{'配置校验','check.log',8192},{'最近异常','last-exit.txt',8192}}
  local rows={};for _,g in ipairs(groups)do rows[#rows+1]='=== '..g[1]..' ===\n'..M.read(M.R..'/'..g[2],g[3])end
  text=table.concat(rows,'\n');text=text:gsub('https?://[^%s]+','[链接已隐藏]')
 end
 H.write(text)
end
function A.upload()
 if H.getenv('REQUEST_METHOD')~='POST'or not csrf()then reply({error='forbidden'},403);return end
 local d=body();if not d or type(d.id)~='string'or not d.id:match('^%x%x%x%x%x%x%x%x$')or not ({source=true,bounds=true,filter=true,mirror=true,policy=true,group=true,profile=true})[d.kind]or type(d.data)~='string'or #d.data>1600000 then reply({error='invalid_upload'},400);return end
 local job=M.load(M.R..'/job.json');if job.active then reply({error='busy'},409);return end
 local ok,raw=pcall(require('nixio').bin.b64decode,d.data);if not ok or not raw then reply({error='invalid_upload'},400);return end
 -- Small requests avoid Xiaomi LuCI's limited form parser. Publish only a complete upload.
 if d.part~=nil then
  local part,total=tonumber(d.part),tonumber(d.total)
  if not part or not total or part%1~=0 or total%1~=0 or total<1 or total>350 or part<0 or part>=total or #d.data>16000 then reply({error='invalid_chunk'},400);return end
  local path=M.R..'/upload-part-'..d.kind;local meta=path..'.json'
  local state=M.load(meta)
  if part==0 then M.write(path,'');state={id=d.id,next=0,total=total,bytes=0} end
  if state.id~=d.id or state.next~=part or state.total~=total or (state.bytes or 0)+#raw>1572864 then reply({error='upload_sequence'},409);return end
  local f=io.open(path,'ab');if not f then reply({error='upload_write_failed'},500);return end
  local written=f:write(raw);f:close();if not written then reply({error='upload_write_failed'},500);return end
  state.next=part+1;state.bytes=(state.bytes or 0)+#raw;M.save(meta,state)
  if state.next<total then reply({ok=true,complete=false});return end
  raw=M.read(path,1572865);if #raw~=state.bytes then reply({error='upload_incomplete'},400);return end
  os.remove(path);os.remove(meta)
 end
 if not pcall(M.write,M.R..'/upload-'..d.kind,raw)then reply({error='upload_write_failed'},500);return end
 M.write(M.R..'/upload-id-'..d.kind,d.id);reply({ok=true,complete=true})
end
function A.control()
 if H.getenv('REQUEST_METHOD')~='POST'or not csrf()then reply({error='forbidden'},403);return end
 local d=body();local allowed={start=true,stop=true,restart=true,clear=true,cleanup=true,memcfg=true,fetch=true,apply=true,dns=true,policy=true,groupmode=true,grouplayout=true,rules=true,domainupdate=true,corecheck=true,coreupdate=true,toolcheck=true,toolupdate=true,guard=true,transport=true,proxymode=true,advanced=true,mirrortest=true,mirrorsave=true,mirrorsync=true,mirrorverify=true,backuplocal=true,backupremote=true}
 if not d or type(d.script)~='string'then reply({error='invalid_action'},400);return end
 local action=d.script:match('^sc%-(%w+)%.sh$');if not allowed[action]then reply({error='unsupported_action'},400);return end
 local args=d.args or {};if type(args)~='table'or #args>3 then reply({error='invalid_arguments'},400);return end;for _,v in ipairs(args)do if type(v)~='string'or #v>100 or not v:match('^[%w+/=]+$')then reply({error='invalid_arguments'},400);return end end
 if not M.lock('operation.lock',900)then reply({error='busy'},409);return end
 local id=args[1]or'';if id~=''and not id:match('^%x%x%x%x%x%x%x%x$')then os.remove(M.R..'/operation.lock');reply({error='invalid_id'},400);return end
 M.save(M.R..'/request.json',{action=action,args=args})
 M.save(M.R..'/job.json',{active=true,phase='working',id=id,message_b64=M.b64('service_operation')})
 M.run('(umask 077; lua '..M.C..'/ax5/job.lua > '..M.R..'/worker.log 2>&1) </dev/null >/dev/null 2>&1 &')
 reply({ok=true})
end
function A.api()
 if not csrf()then reply({error='forbidden'},403);return end
 local path=H.formvalue('path')or'';local method=H.getenv('REQUEST_METHOD');if method=='POST'then method=path=='/configs'and'PATCH'or'PUT'end
 if path=='/panel-traffic' then
  if method~='GET'then reply({error='read_only'},403);return end
  local pid=M.pid();if pid==0 then reply({running=false});return end
  local stat=M.read('/proc/'..pid..'/stat'):match('^%d+ %(.+%) (.+)$')or'';local fields={};for v in stat:gmatch('%S+')do fields[#fields+1]=v end
  local raw=M.exec('curl --noproxy "*" -sN --connect-timeout 1 --max-time 1.5 -H '..M.quote(M.read(M.C..'/configs/api-header'):gsub('%s+$',''))..' http://127.0.0.1:9999/traffic 2>/dev/null | head -1')
  local ok,v=pcall(M.json.decode,raw)
  if not ok or type(v)~='table'or M.pid()~=pid or type(v.up)~='number'or type(v.down)~='number'or type(v.upTotal)~='number'or type(v.downTotal)~='number'then reply({error='traffic_unavailable'},503);return end
  v.running=true;v.epoch=tostring(pid)..'-'..tostring(fields[20]);v.checked_ms=math.floor((tonumber(M.read('/proc/uptime'):match('^(%S+)'))or 0)*1000)
  reply(v);return
 end
 if path:match('^/panel%-probe/')then
  local urls={baidu='https://www.baidu.com/',bilibili='https://www.bilibili.com/favicon.ico',tencentqq='https://www.qq.com/favicon.ico',taobao='https://www.taobao.com/favicon.ico',google='https://www.google.com/generate_204',youtube='https://www.youtube.com/generate_204',github='https://github.com/favicon.ico',openai='https://chatgpt.com/favicon.ico'}
  local url=urls[path:match('^/panel%-probe/([a-z]+)$')or''];if method~='GET'or not url then reply({error='invalid_probe'},400);return end
  -- Respect the active core rules. This router-originated request is distinct
  -- from a forced outbound delay and from a LAN client's existing connection.
  local output=M.exec('curl -4 -sS -I --proxy http://127.0.0.1:7890 --noproxy "" --connect-timeout 5 --max-time 8 -o /dev/null -w '..M.quote('%{http_code} %{time_total} %{ssl_verify_result}')..' '..M.quote(url)..' 2>/dev/null')
  local http,seconds,tls=output:match('(%d%d%d) ([%d%.]+) (%d+)');http,seconds,tls=tonumber(http)or 0,tonumber(seconds)or 0,tonumber(tls)or 1
  reply({http=http,delay=http>0 and tls==0 and math.max(1,math.floor(seconds*1000))or 0,scope='router-rules',tls=tls});return
 end
 if #path>2048 or path:find('[\r\n]')or not (path=='/version'or path=='/configs'or path=='/rules'or path=='/providers/proxies'or path=='/providers/rules'or path=='/connections'or path:match('^/connections/[A-Za-z0-9%-]+$')or path=='/proxies'or path:match('^/proxies/')or path:match('^/group/[^/]+/delay'))or not ({GET=true,PUT=true,DELETE=true,PATCH=true})[method]then reply({error='invalid_api'},400);return end
 if (method=='PUT'or method=='DELETE')and not(path:match('^/proxies/')or method=='DELETE'and path:match('^/connections/[A-Za-z0-9%-]+$'))then reply({error='read_only'},403);return end
 if method=='PATCH'then
  if path~='/configs'then reply({error='read_only'},403);return end
  local d=body();if not d or not({rule=true,direct=true,global=true})[d.mode]then reply({error='invalid_mode'},400);return end
  for k in pairs(d)do if k~='mode'then reply({error='invalid_mode'},400);return end end
  if not M.lock('operation.lock',900)then reply({error='busy'},409);return end
  local ok,err=pcall(function()dofile(M.C..'/ax5/traffic-mode.lua').apply(d.mode)end)
  os.remove(M.R..'/operation.lock')
  if not ok then reply({error=tostring(err)},503);return end
  reply({ok=true});return
 end
 local data='';if method=='PUT'then local d=body();if not d or type(d.name)~='string'or #d.name>256 then reply({error='invalid_node'},400);return end;data=M.json.encode({name=d.name}) end
 if method=='GET'then
  local stream,status=dofile(M.C..'/ax5/core-stream.lua').open(path)
  if not stream then reply({error='core_request_failed'},status>0 and status or 503);return end
  H.status(status);H.header('Cache-Control','no-store');H.prepare_content('application/json')
  while true do local block=stream:read(4096);if not block then break end;H.write(block)end
  stream:close();return
 end
 local raw,status=M.request(path,method,data)
 if status<200 or status>=300 then reply({error='core_request_failed'},status>0 and status or 503);return end
 if method~='GET'then reply({ok=true});return end
 local ok,v=pcall(M.json.decode,raw);if not ok then reply({error='core_unavailable'},503);return end;H.prepare_content('application/json');H.write(raw)
end
function A.advancedasset()
 local parts={};local found=false
 for _,v in ipairs(D.context.request or{})do if found then parts[#parts+1]=v elseif v=='advancedasset'then found=true end end
 local name=table.concat(parts,'/');if name==''then name='index.html'end
 if #name>180 or name:find('..',1,true)or not name:match('^[%w_./-]+$')or not name:match('%.%w+$')then reply({error='not_found'},404);return end
 local types={html='text/html',js='application/javascript',css='text/css',png='image/png',ico='image/x-icon',svg='image/svg+xml',webmanifest='application/manifest+json'};local ext=name:match('%.(%w+)$');if not types[ext]then reply({error='not_found'},404);return end
 local raw=M.read('/tmp/ShellCrash-dashboard/'..name,1048576);if raw==''then reply({error='not_found'},404);return end
 H.header('Cache-Control','no-store');H.prepare_content(types[ext]);H.write(raw)
end
return A
