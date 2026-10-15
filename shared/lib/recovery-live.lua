-- Server-side snapshot; called only by the authenticated recovery supervisor.
local model,remote=arg[1],arg[2]
assert(model=='ax5'or model=='k2p','invalid profile')
assert(remote and #remote==64 and not remote:find('[^a-f0-9]'),'invalid remote fingerprint')
local json=require('cjson')
local function read(path,limit)local f=assert(io.open(path,'rb'));local s=f:read((limit or 8192)+1);f:close();assert(#s<=(limit or 8192),'input exceeds limit');return s end
local function run(cmd)local p=assert(io.popen(cmd));local s=p:read('*a');p:close();return (s:gsub('%s+$',''))end
local function hash(path)
 local command=model=='ax5'and'openssl dgst -sha256 'or'sha256sum '
 local s=run(command..path);local h=model=='ax5'and s:match('(%x+)$')or s:match('^(%x+)');assert(h and #h==64,'hash unavailable');return h
end
local runtime=model=='ax5'and'/tmp/ShellCrash'or'/tmp/sc-admin'
local revision=io.open(runtime..'/recovery-revision');local operation_revision=revision and tonumber(revision:read('*a'))or 0;if revision then revision:close()end
local C=model=='ax5'and'/data/ShellCrash'or'/etc/storage/ShellCrash'
local pid=assert(tonumber(run('pidof CrashCore')),'a single running core is required')
local live={operation_revision=operation_revision or 0,pid=pid,remote_fingerprint=remote,machine=run('uname -m'),boot_id=read('/proc/sys/kernel/random/boot_id'):gsub('%s+$',''),
 uptime=assert(tonumber(read('/proc/uptime'):match('^(%S+)'))),available_kb=assert(tonumber(run("awk '/MemAvailable:/{print $2;exit}' /proc/meminfo"))),
 binary_sha256=hash('/proc/'..pid..'/exe'),binary_size=assert(tonumber(run('wc -c < /proc/'..pid..'/exe')))}
local cmd='find '..C..'/configs -type f -exec '..(model=='ax5'and'openssl dgst -sha256'or'sha256sum')..' {} \\; | sort | '..(model=='ax5'and'openssl dgst -sha256'or'sha256sum')
local raw=run(cmd);live.config_fingerprint=model=='ax5'and raw:match('(%x+)$')or raw:match('^(%x+)');assert(#live.config_fingerprint==64)
if model=='ax5'then
 local M=dofile(C..'/ax5/common.lua');local state=M.state()
 live.core_sha256=hash(C..'/cache/core-armv7.tar.gz');assert(live.core_sha256==read(C..'/cache/core.sha256'):gsub('%s+$',''),'installed core hash mismatch')
 live.core_kind=state.core_kind;live.core_version=state.core_version;live.protect_mb=M.limits().protect_mb
 live.enabled=state.enabled and 1 or 0;live.autostart=state.autostart and 1 or 0;live.traffic_mode=state.traffic_mode
 live.core_size=tonumber(run('wc -c < '..C..'/cache/core-armv7.tar.gz'))
 local stat=read('/proc/'..pid..'/statm');local _,resident,shared=stat:match('^(%d+)%s+(%d+)%s+(%d+)')
 live.private_rss_kb=math.max(0,tonumber(resident)-tonumber(shared))*4
 live.flash_free_kb=tonumber(run("df -Pk /data | awk 'END{print $4}'"))
 live.application_kb=tonumber(run("du -sk /data/ShellCrash/ax5 /data/ShellCrash/ui /data/ShellCrash/configs /data/ShellCrash/ruleset /data/ShellCrash-tool /data/ShellCrash/cache/targets | awk '{n+=$1}END{print n}'"))
else
 local core={};for k,v in read(C..'/configs/core-installed.info',2048):gmatch('([%w_]+)=([^\r\n]+)')do assert(core[k]==nil,'duplicate core record');core[k]=v end
 assert(core.arch=='mipsle-softfloat'and core.variant=='singbox','unsupported K2P core')
 live.core_sha256=core.sha256;live.core_version=core.version;live.core_kind='singbox'
 local mem=io.open(C..'/configs/memory.conf');local cfg=mem and mem:read('*a')or'';if mem then mem:close()end
 live.protect_mb=tonumber(cfg:match('protect_mb=(%d+)'))or 12
 local function exists(path)local f=io.open(path);if f then f:close();return true end;return false end
 live.enabled=exists(C..'/configs/panel-disabled')and 0 or 1
 live.autostart=exists(C..'/.dis_startup')and 0 or 1
 local mode=io.open('/tmp/ShellCrash/traffic-mode');live.traffic_mode=mode and mode:read('*l')or'rule';if mode then mode:close()end
end
assert(live.protect_mb>=12 and live.protect_mb<=64,'invalid protection setting')
assert(live.core_sha256 and #live.core_sha256==64 and not live.core_sha256:find('[^a-f0-9]'),'invalid core record')
assert(live.core_version and live.core_version:match('^v?[0-9][%w._+%-]*$'),'invalid core version')
live.startup_fingerprint=hash(model=='ax5'and'/etc/init.d/shellcrash'or C..'/start.sh')
print(json.encode(live))
