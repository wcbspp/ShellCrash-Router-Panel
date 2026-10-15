-- Private server-generated plans and single-use monotonic confirmation tickets.
-- The browser can submit only the id and opaque token, never this plan/context.
local action,x=arg[1],arg[2]
assert(x and x:match('^/tmp/sc%-preflight%-%x%x%x%x%x%x%x%x$'),'invalid recovery session')
local id=x:sub(-8);local json=require('cjson')
local function load(name,limit)
 local f=assert(io.open(x..'/'..name,'rb'));local raw=f:read((limit or 20000)+1);f:close();assert(#raw<=(limit or 20000),'session input exceeds limit');return json.decode(raw)
end
local function write(name,raw)local f=assert(io.open(x..'/'..name..'.new','wb'));assert(f:write(raw));assert(f:close());assert(os.rename(x..'/'..name..'.new',x..'/'..name))end
local function save(name,obj)write(name,json.encode(obj))end
local function sha(s)assert(type(s)=='string'and #s==64 and not s:find('[^a-f0-9]'),'invalid SHA256');return s end
local function safe(path)
 assert(type(path)=='string'and #path<220 and path:match('^[%w_./%-]+$')and path:sub(1,1)~='/','invalid component path')
 for part in (path..'/'):gmatch('(.-)/')do assert(part~=''and part~='.'and part~='..','component traversal')end
 return path
end
local function digest(name)
 assert(name:match('^[%w_.%-]+$'),'invalid private control file')
 local path=x..'/'..name;local output=x..'/digest.tmp'
 assert(os.execute('if type sha256sum >/dev/null 2>&1;then sha256sum '..path..';else openssl dgst -sha256 '..path..';fi > '..output)==0,'control file digest failed')
 local f=assert(io.open(output,'rb'));local raw=f:read(1024);f:close()
 for value in raw:gmatch('%x+')do if #value==64 then return value end end
 error('control digest missing')
end
local function now()local f=assert(io.open('/proc/uptime'));local n=assert(tonumber(f:read('*l'):match('^(%S+)')));f:close();return n end
local bindings={'operation_revision','remote_fingerprint','config_fingerprint','startup_fingerprint','pid','boot_id','binary_sha256','core_sha256','core_kind','core_version','enabled','autostart','traffic_mode'}
if action=='plan'then
 local b,live,s=load('backup.json'),load('live.json'),load('selection.json')
 assert(b.model=='AX5'or b.model=='K2P','invalid model')
 assert(b.core_version==live.core_version and b.core_kind==live.core_kind,'page recovery currently requires the same core version and kind')
 local records={};for _,r in ipairs(b.files)do records[r.name]=r end
 assert(records['core.tar.gz'].sha256==live.core_sha256,'page recovery currently requires the same core archive')
 local p={id=id,manifest_sha256=sha(s.manifest_sha256),remote_fingerprint=sha(live.remote_fingerprint),core_sha256=sha(live.core_sha256),
  core_version=live.core_version,binary_sha256=sha(live.binary_sha256),binary_size=live.binary_size,protect_kb=live.protect_mb*1024,
  previous_core_sha256=live.core_sha256,previous_core_kind=live.core_kind,previous_core_version=live.core_version,target_core_version=b.core_version,
  previous_enabled=live.enabled,previous_autostart=live.autostart,previous_mode=live.traffic_mode,rehearsal_failure='none'}
 for _,pair in ipairs({{'application.tar.gz','application'},{'core.tar.gz','core'},{'runtime-assets.tar.gz','runtime'}})do
  local r=assert(records[pair[1]]);assert(type(r.size)=='number'and r.size>0 and r.size%1==0 and r.size<=40000000,'invalid component size')
  p[pair[2]..'_path']=safe((s.prefix or'')..r.path);p[pair[2]..'_size']=r.size;p[pair[2]..'_sha256']=sha(r.sha256)
 end
 -- Placeholder values are replaced from the router's native archive summaries.
 save('server-plan.json',p)
elseif action=='finalize'then
 local p,a,r,live=load('server-plan.json'),load('application.json'),load('runtime.json'),load('live.json')
 assert(a.model==r.model and a.component=='application'and r.component=='runtime-assets','native archive results missing')
 p.peak_bytes=live.binary_size+a.unpacked_size+r.unpacked_size+p.application_size+p.runtime_size+(a.model=='K2P'and 6291456 or 2097152)
 p.tmp_bytes=p.peak_bytes;p.boot_core_bytes=live.binary_size;p.boot_private_kb=(live.private_rss_kb or 0)+1024
 if a.model=='K2P'then
  assert(a.core_version==live.core_version,'internal version mismatch')
  p.target_enabled=a.enabled;p.target_autostart=a.autostart;p.target_mode=a.traffic_mode
 else assert(a.unpacked_size+524288<=(live.flash_free_kb+live.application_kb)*1024,'insufficient flash space')end
 assert(live.available_kb>=live.protect_mb*1024+3072,'insufficient memory')
 local rows={};for k,v in pairs(p)do
  assert(type(v)=='number'or type(v)=='string','invalid execution field')
  v=tostring(v);assert(not v:find('[\r\n]'),'invalid execution value');rows[#rows+1]=k..'='..v..'\n'
 end
 table.sort(rows);write('plan',table.concat(rows));save('server-plan.json',p)
elseif action=='seal'then
 local passed=load('passed.json');assert(passed.archive_checked and passed.config_checked and passed.core_checked,'native preflight incomplete')
 local live,p,s=load('live.json'),load('server-plan.json'),load('selection.json')
 local f=assert(io.open('/dev/urandom','rb'));local raw=assert(f:read(8));f:close();assert(#raw==8)
 local token=raw:gsub('.',function(c)return string.format('%02x',c:byte())end)
 local stamp=now();local ticket={token=token,created=stamp,expires=stamp+180,live=live,manifest_sha256=p.manifest_sha256,plan_sha256=digest('plan'),worker_sha256=digest('restore-worker.sh')}
 save('ticket.json',ticket)
 local out={id=id,source=s.source,checked=os.time(),verified=true,executor_ready=passed.enabled==true,archive_checked=true,config_checked=true,
  manifest_sha256=p.manifest_sha256,token=token,expires_in=180,backup=load('backup.json')}
 save('public.json',out)
elseif action=='take'or action=='check'then
 local ticket,current,s=load('ticket.json'),load('current.json'),load('selection.json')
 assert(type(arg[3])=='string'and #arg[3]==16 and not arg[3]:find('[^a-f0-9]')and arg[3]==ticket.token,'confirmation ticket mismatch')
 if action=='take'then assert(os.rename(x..'/ticket.json',x..'/ticket-used.json'),'confirmation ticket already used')end
 local stamp=now();assert(stamp>=ticket.created and stamp<=ticket.expires,'confirmation ticket expired')
 assert(s.manifest_sha256==ticket.manifest_sha256,'manifest changed')
 assert(digest('plan')==ticket.plan_sha256 and digest('restore-worker.sh')==ticket.worker_sha256,'private execution plan or worker changed')
 for _,key in ipairs(bindings)do assert(current[key]==ticket.live[key],'device or remote state changed: '..key)end
 -- The atomic transition precedes state checks: a changed/expired ticket
 -- cannot become valid again if the old state is later restored.
elseif action=='invalidate'then
 local f=io.open(x..'/ticket.json');if f then local t=json.decode(f:read(20000));f:close();if t.token==arg[3]then os.rename(x..'/ticket.json',x..'/ticket-invalid.json')end end
elseif action=='result'then
 local f=assert(io.open('/tmp/sc-restore-'..id..'/result.json'));local r=json.decode(f:read(4096));f:close();assert(r.id==id,'result identity mismatch')
 local public=load('public.json');public.token=nil;public.executor_ready=false;public.execution=r;save('public.json',public)
elseif action=='running'then
 local public=load('public.json');public.token=nil;public.executor_ready=false;public.execution={id=id,state='running'};save('public.json',public)
else error('unknown session action')end
