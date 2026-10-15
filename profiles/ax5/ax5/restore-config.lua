-- Structural native conversion with isolated file references. The full core
-- check runs in the independent transaction after pausing the memory-heavy core.
local x=assert(arg[1]);assert(x:match('^/tmp/sc%-preflight%-%x%x%x%x%x%x%x%x$')or x:match('^/tmp/sc%-restore%-%x%x%x%x%x%x%x%x$'))
local json=require('cjson');local function read(p)local f=assert(io.open(p,'rb'));local v=f:read('*a');f:close();return v end
local c=json.decode(read(x..'/config.original.json'));assert(type(c.outbounds)=='table'and #c.outbounds>0,'invalid outbounds')
local live=json.decode(read(x..'/live.json'))
local cfg=c
if live.core_kind=='meta'then
 local p=io.open(x..'/app/configs/policy.tsv');if p then c._subscription_policy=p:read('*a');p:close()end
 cfg=dofile('/data/ShellCrash/ax5/mihomo.lua').build(c)
 for _,kind in ipairs({'rule-providers','proxy-providers'})do for _,v in pairs(cfg[kind]or{})do v.type='file';v.url=nil end end
end
local function rewrite(t,depth,context)
 assert(t.type~='remote'or t.url==nil,'remote resources cannot be checked offline')
 assert(depth<64,'configuration nesting exceeds limit')
 for k,v in pairs(t)do
  if type(v)=='table'then rewrite(v,depth+1,k)
  elseif type(v)=='string'then
   if k=='path'and context~='transport'then
    if v:sub(1,#'/data/ShellCrash/')=='/data/ShellCrash/'then v=x..'/app/'..v:sub(#'/data/ShellCrash/'+1)
    elseif v:sub(1,#'/tmp/ShellCrash/ruleset/')=='/tmp/ShellCrash/ruleset/'then v=x..'/runtime/ShellCrash/ruleset/'..v:sub(#'/tmp/ShellCrash/ruleset/'+1)
    else error('unsupported configuration file reference')end
    assert(not v:find('/../',1,true)and not v:find('/./',1,true),'file traversal')
    local f=assert(io.open(v,'rb'),'backup resource missing');f:close();t[k]=v
   elseif k=='certificate_path'or k=='key_path'then error('external certificate/key path unsupported')end
  end
 end
end
if cfg.experimental and cfg.experimental.cache_file then cfg.experimental.cache_file.enabled=false;cfg.experimental.cache_file.path=nil end
if cfg.log then cfg.log.output=x..'/core-check.log'end
rewrite(cfg,0)
-- Mihomo reads this JSON through its YAML loader, which rejects JSON's optional
-- escaped forward slash. Match the production configuration writer.
local f=assert(io.open(x..'/config.check.json','wb'));assert(f:write((json.encode(cfg):gsub('\\/','/'))));assert(f:close())
