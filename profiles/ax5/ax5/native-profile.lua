-- Keep upstream native strategy/rules as the source of truth; local routing is an overlay.
local M=dofile('/data/ShellCrash/ax5/common.lua')
local P=dofile(M.C..'/ax5/policy.lua')
local N=dofile(M.C..'/ax5/node-identity.lua')
local A={}
local function copy(v)return M.json.decode(M.json.encode(v))end
function A.import(c,base)
 c._subscription_warnings={}
 assert(type(base)=='table'and type(base.proxies)=='table'and type(base['proxy-groups'])=='table'and type(base.rules)=='table','ShellCrash 未返回完整 Mihomo 配置；当前配置保留')
 assert(#base.proxies>0 and #base.proxies<=500 and #base['proxy-groups']<=100 and #base.rules<=40000,'模板配置超过轻量设备上限')
 -- Country.cnmini intentionally contains only CN. Other GeoIP categories must never
 -- silently miss and fall through as though a full database was installed.
 for _,rule in ipairs(base.rules)do local name=rule:match('^GEOIP,([^,]+)');assert(not name or name:lower()=='cn'or name:lower()=='private','模板需要完整 GeoIP 分类数据库（'..tostring(name)..'）；当前轻量数据库只含国内 IP，请改用不依赖完整 GeoIP 的模板。当前配置保留')end
 local out,known,nodes={},{},{}
 for _,p in ipairs(base.proxies)do
  assert(type(p.name)=='string'and #p.name<=256 and not known[p.name],'模板节点名称重复或无效')
  local n={tag=p.name,type=({ss='shadowsocks',ssr='shadowsocksr'})[p.type]or p.type,server=p.server,server_port=p.port,password=p.password,uuid=p.uuid,method=p.cipher,protocol=p.protocol,protocol_param=p['protocol-param'],obfs=p.obfs,obfs_param=p['obfs-param']}
  known[n.tag]=n;out[#out+1]=n;nodes[#nodes+1]=n.tag
 end
 local _,renamed=N.preserve(c.outbounds,out)
 known={};nodes={};for _,n in ipairs(out)do known[n.tag]=n;nodes[#nodes+1]=n.tag end
 for _,p in ipairs(base.proxies)do p.name=renamed[p.name]or p.name end
 for _,g in ipairs(base['proxy-groups'])do
  assert(type(g.name)=='string'and not known[g.name]and not g.name:match('^分流/'),'模板策略组名称重复或使用了面板保留名称')
  for i,name in ipairs(g.proxies or{})do g.proxies[i]=renamed[name]or name end
  local refs=copy(g.proxies or{});local n={type=g.type=='url-test'and'urltest'or'selector',tag=g.name,outbounds=refs}
  known[n.tag]=n;out[#out+1]=n
 end
 -- Preserve exact node references inside template rule targets.
 for i,r in ipairs(base.rules)do
  assert(type(r)=='string','模板规则格式无效')
  local prefix,target,tail=r:match('^(.*),([^,]+),(no%-resolve)$')
  if not prefix then prefix,target=r:match('^(.*),([^,]+)$');tail=nil end
  if target and renamed[target]then base.rules[i]=prefix..','..renamed[target]..(tail and','..tail or'')end
 end
 local primary
 for _,r in ipairs(base.rules)do local t=r:match('^MATCH,([^,]+)');if t and known[t]then primary=t end end
 primary=primary or(base['proxy-groups'][1]and base['proxy-groups'][1].name)
 assert(primary,'模板缺少默认策略组')
 out[#out+1]={type='direct',tag='direct'};known.direct=out[#out]
 if not known.DIRECT then out[#out+1]={type='selector',tag='DIRECT',outbounds={'direct'},default='direct'};known.DIRECT=out[#out]end
 if not known.REJECT then out[#out+1]={type='block',tag='REJECT'};known.REJECT=out[#out]end
 -- Existing local overrides can keep their former group names without replacing template groups.
 local required={['proxy-main']=true};for _,g in ipairs(c.outbounds or{})do if g.tag:match('^分流/')and g.default and M.read(M.C..'/configs/policy.tsv'):find('\t'..g.tag..'\n',1,true)then required[g.default]=true end end
 for line in M.read(M.C..'/configs/policy.tsv'):gmatch('[^\n]+')do local t=line:match('\t([^\t]+)$');if t then required[t]=true end end
 for _,g in ipairs(c.outbounds or{})do
  if required[g.tag]and not known[g.tag]and g.outbounds and not g.tag:match('^分流/')then
   local members={};for _,n in ipairs(g.outbounds)do if known[n]then members[#members+1]=n end end
   if g.tag=='proxy-main'then members={primary}end
   if #members==0 then members={primary};c._subscription_warnings[#c._subscription_warnings+1]=g.tag..' 不在新订阅中，已重置为默认代理' end
   local alias={type='selector',tag=g.tag,outbounds=members,default=members[1]};known[g.tag]=alias;out[#out+1]=alias
  end
 end
 if not known['proxy-main']then out[#out+1]={type='selector',tag='proxy-main',outbounds={primary},default=primary};known['proxy-main']=out[#out]end
 for _,g in ipairs(c.outbounds or{})do if g.tag:match('^分流/')and required[g.tag]then local v=copy(g);out[#out+1]=v;known[g.tag]=v end end
 if not known.GLOBAL then out[#out+1]={type='selector',tag='GLOBAL',outbounds={'proxy-main'},default='proxy-main'}end
 c.outbounds=out;c._native_meta=base;c._template_kind='meta'
 c._subscription_policy=P.reconcile(c,M.read(M.C..'/configs/policy.tsv'))
 P.groups(c,P.parse(c._subscription_policy,c))
 -- Native provider groups may populate dynamically, but explicit members must be valid.
 N.validate_targets(c)
 return c
end
function A.import_singbox(old,base)
 assert(type(base)=='table'and type(base.outbounds)=='table'and type(base.route)=='table'and type(base.route.rules)=='table','ShellCrash 未返回完整 sing-box 配置；当前配置保留')
 assert(#base.outbounds<=600 and #base.route.rules<=40000,'模板配置超过轻量设备上限')
 local c=copy(base);c._subscription_warnings={};local _,renamed=N.preserve(old.outbounds,c.outbounds)
 local known={};for _,o in ipairs(c.outbounds)do assert(type(o.tag)=='string'and not known[o.tag],'模板节点或策略组重名');known[o.tag]=o end
 for _,r in ipairs(c.route.rules)do if r.outbound then r.outbound=renamed[r.outbound]or r.outbound end end
 local primary=c.route.final;for _,o in ipairs(c.outbounds)do if not primary and o.type=='selector'then primary=o.tag end end
 assert(primary and known[primary],'模板缺少默认代理组')
 if not known.direct then local n={type='direct',tag='direct'};c.outbounds[#c.outbounds+1]=n;known.direct=n end
 local required={['proxy-main']=true};for _,g in ipairs(old.outbounds or{})do if g.tag:match('^分流/')and g.default and M.read(M.C..'/configs/policy.tsv'):find('\t'..g.tag..'\n',1,true)then required[g.default]=true end end;for line in M.read(M.C..'/configs/policy.tsv'):gmatch('[^\n]+')do local t=line:match('\t([^\t]+)$');if t then required[t]=true end end
 for _,g in ipairs(old.outbounds or{})do
  if required[g.tag]and not known[g.tag]and g.outbounds and not g.tag:match('^分流/')then
   local refs={};for _,n in ipairs(g.outbounds)do if known[n]then refs[#refs+1]=n end end;if g.tag=='proxy-main'then refs={primary}end
   if #refs==0 then refs={primary};c._subscription_warnings[#c._subscription_warnings+1]=g.tag..' 不在新订阅中，已重置为默认代理' end
   local alias={type='selector',tag=g.tag,outbounds=refs,default=refs[1]};known[g.tag]=alias;c.outbounds[#c.outbounds+1]=alias
  end
 end
 if not known['proxy-main']then c.outbounds[#c.outbounds+1]={type='selector',tag='proxy-main',outbounds={primary},default=primary}end
 for _,g in ipairs(old.outbounds or{})do if g.tag:match('^分流/')and required[g.tag]then assert(not known[g.tag],'模板使用了面板保留分流名称');c.outbounds[#c.outbounds+1]=copy(g)end end
 c.dns=old.dns;c.inbounds=old.inbounds;c.experimental=old.experimental;c.log=old.log;c._template_kind='singbox'
 local safe={};for _,r in ipairs(old.route.rules or{})do if r.action=='hijack-dns'or r.action=='sniff'or r.ip_is_private then safe[#safe+1]=copy(r)end end
 for _,r in ipairs(c.route.rules)do safe[#safe+1]=r end;c.route.rules=safe
 c._subscription_policy=P.reconcile(c,M.read(M.C..'/configs/policy.tsv'));local rows=P.groups(c,P.parse(c._subscription_policy,c));P.apply(c,rows,{})
 N.validate_targets(c);return c
end
function A.merge(c,runtime)
 local base=copy(c._native_meta)
 for _,key in ipairs({'mixed-port','redir-port','allow-lan','bind-address','mode','log-level','ipv6','routing-mark','find-process-mode','external-controller','secret','profile','hosts','dns'})do base[key]=runtime[key]end
 -- Template data cannot open extra listeners or replace the router's managed network stack.
 for _,key in ipairs({'port','socks-port','tproxy-port','listeners','external-controller-tls','external-controller-unix','external-ui','external-ui-url','authentication','interface-name'})do base[key]=nil end
 base.tun=runtime.tun or {enable=false};base['geo-auto-update']=false;base['geodata-mode']=false;base['geodata-loader']='memconservative'
 local known={};for _,g in ipairs(base['proxy-groups'])do known[g.name]=true end
 for _,g in ipairs(runtime['proxy-groups'])do if not known[g.name]then base['proxy-groups'][#base['proxy-groups']+1]=g;known[g.name]=true end end
 local rules={};for _,r in ipairs(runtime.rules)do if r:match('^IP%-CIDR,')and #rules<8 then rules[#rules+1]=r else break end end
 for _,r in ipairs(P.parse(c._subscription_policy or M.read(M.C..'/configs/policy.tsv'),c))do
  rules[#rules+1]=(r.domain and'DOMAIN,'or'DOMAIN-SUFFIX,')..(r.domain or r.domain_suffix)[1]..','..(r.outbound=='direct'and'DIRECT'or r.outbound)
 end
 for _,r in ipairs(base.rules)do rules[#rules+1]=r end;base.rules=rules
 base['rule-providers']=base['rule-providers']or{}
 assert(not base['rule-providers'].cn,'模板使用了本机保留的 cn 规则库名称')
 base['rule-providers'].cn=runtime['rule-providers'].cn
 for _,field in ipairs({'rule-providers','proxy-providers'})do
  for name,p in pairs(base[field]or{})do
   if name~='cn'or field~='rule-providers'then
    assert(type(name)=='string'and #name<=64,'规则库名称过长')
    local escaped=name:gsub('.',function(x)return string.format('%02x',x:byte())end)
    assert(p.type~='file','模板本地规则库必须先通过 ShellCrash 安装，当前配置保留')
    p.path=M.C..'/ruleset/native/'..field..'-'..escaped..'.yaml'
   end
  end
 end
 return base
end
return A
