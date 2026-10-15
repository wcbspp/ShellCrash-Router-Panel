-- Prepare an isolated sing-box check. No scripts or network rules are loaded.
local x=assert(arg[1]);assert(x:match('^/tmp/sc%-preflight%-%x%x%x%x%x%x%x%x$'),'invalid preflight directory')
local json=require('cjson')
local f=assert(io.open(x..'/config.original.json','rb'));local raw=f:read(1500001);f:close()
assert(#raw<=1500000,'configuration exceeds limit')
local config=json.decode(raw);assert(type(config)=='table'and type(config.outbounds)=='table','invalid configuration')
local function rewrite(value,depth,context)
 assert(depth<64,'configuration nesting exceeds limit')
 if type(value)~='table'then return end
 assert(value.type~='remote'or value.url==nil,'remote resources cannot be checked offline')
 for k,v in pairs(value)do
  if type(v)=='table'then rewrite(v,depth+1,k)
  elseif type(v)=='string'then
   if k=='path'and context~='transport'then
    local relative=v:match('^/tmp/ShellCrash/ruleset/([A-Za-z0-9_.-]+)$')or v:match('^ruleset/([A-Za-z0-9_.-]+)$')
    assert(relative and relative~='.'and relative~='..','unsupported configuration file reference')
    local candidate=x..'/runtime/ShellCrash/ruleset/'..relative
    local rule=assert(io.open(candidate,'rb'),'backup rule resource missing');rule:close();value[k]=candidate
   elseif k=='certificate_path'or k=='key_path'or k=='ech_key_path'then error('external key/certificate file is unsupported')
   end
  end
 end
end
-- These writable paths must never refer to the running service during a check.
if config.log then config.log.output=x..'/core-check.log' end
if config.experimental and config.experimental.cache_file then config.experimental.cache_file.path=nil;config.experimental.cache_file.enabled=false end
if config.experimental and config.experimental.clash_api then config.experimental.clash_api.external_ui=x..'/runtime/ShellCrash-dashboard' end
rewrite(config,0)
f=assert(io.open(x..'/config.check.json','wb'));assert(f:write(json.encode(config)));assert(f:close())
