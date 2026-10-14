local root=arg[1]or'/data/ShellCrash/ax5'
local original=dofile;local M=original(root..'/common.lua');local read=M.read;local interception='Redir模式';local policy="suffix\tcustom.example\tproxy-main\n"
M.read=function(p,max)if p=='/data/ShellCrash-tool/configs/ShellCrash.cfg'then return 'redir_mod='..interception..'\n' elseif p==M.C..'/configs/policy.tsv'then return policy elseif p==M.C..'/configs/fake_ip_filter.list'then return ''end;return read(p,max)end
dofile=function(p)if p:match('/common.lua$')then return M end;local n=p:match('/ax5/([^/]+)$');if n then return original(root..'/'..n)end;return original(p)end
local N=dofile(M.C..'/ax5/native-profile.lua')
local function old()return {outbounds={{type='anytls',tag='node',server='server.example',server_port=443,password='fixture'},{type='selector',tag='proxy-main',outbounds={'node'},default='node'},{type='direct',tag='direct'}},dns={servers={{type='fakeip'}}},route={rules={{ip_is_private=true,outbound='direct'}}},experimental={clash_api={secret='fixture'}}}end
local function meta()return {proxies={{type='anytls',name='decorated',server='server.example',port=443,password='fixture'}},['proxy-groups']={{name='Acl4SSR',type='select',proxies={'decorated','Auto'}},{name='Auto',type='url-test',url='https://www.gstatic.com/generate_204',interval=600,proxies={'decorated'}}},rules={'DOMAIN-SUFFIX,template.example,Acl4SSR','MATCH,Acl4SSR'}}end
local stale=old();stale.outbounds[#stale.outbounds+1]={type='selector',tag='分流/谷歌',outbounds={'removed-node'},default='removed-node'}
assert(pcall(N.import,stale,meta()),'inactive local group must not block native import')
local saved_policy=policy;policy='suffix\tgoogle.com\t分流/谷歌\nsuffix\tgstatic.com\t分流/谷歌\nsuffix\tgoogleapis.com\t分流/谷歌\n'
local active=old();active.outbounds[#active.outbounds+1]={type='selector',tag='分流/谷歌',outbounds={'removed-node'},default='removed-node'};local repaired=N.import(active,meta());local fixed;for _,g in ipairs(repaired.outbounds)do if g.tag=='分流/谷歌'then fixed=g end end;assert(fixed.default=='proxy-main'and #repaired._subscription_warnings==1,'missing fixed target falls back explicitly, without rejecting upstream')
policy='suffix\tcustom.example\tremoved-node\n';local custom=N.import(old(),meta());assert(custom._subscription_policy:find('proxy-main',1,true)and #custom._subscription_warnings==1);assert(policy:find('removed-node',1,true),'staging must not mutate saved policy')
policy=saved_policy
local cn=meta();table.insert(cn.rules,1,'GEOIP,CN,Acl4SSR');assert(pcall(N.import,old(),cn),'CN GeoIP is supported by the mini database')
local foreign=meta();table.insert(foreign.rules,1,'GEOIP,telegram,Acl4SSR');local ok,err=pcall(N.import,old(),foreign);assert(not ok and tostring(err):find('只含国内 IP',1,true),'Non-CN GeoIP must fail before replacing the configuration')
local c=N.import(old(),meta());local built=dofile(M.C..'/ax5/mihomo.lua').build(c)
assert(built.proxies[1].name=='node'and built['proxy-groups'][2].type=='url-test')
assert(built.rules[#built.rules]=='MATCH,Acl4SSR')
assert(built.rules[9]=='DOMAIN-SUFFIX,custom.example,proxy-main')
assert(built.rules[10]=='DOMAIN-SUFFIX,template.example,Acl4SSR')
assert(built.rules[#built.rules-1]=='RULE-SET,panel-cn-ip,DIRECT')
assert(built['rule-providers']['panel-cn-ip'].path==M.C..'/configs/cn_ip.txt')
policy='';c._subscription_policy=nil -- publication clears the staged policy
local followed=dofile(M.C..'/ax5/mihomo.lua').build(c)
assert(#followed.rules==11 and followed.rules[9]=='DOMAIN-SUFFIX,template.example,Acl4SSR')
assert(followed.rules[10]=='RULE-SET,panel-cn-ip,DIRECT'and followed.rules[11]=='MATCH,Acl4SSR')
policy='suffix\tcustom.example\tproxy-main\n'
assert(built['external-controller']=='127.0.0.1:9999'and built['mixed-port']==7890)
assert(built['rule-providers'].cn.type=='file')
local invalid=meta();invalid['proxy-providers']={bad={type='file',path='/etc/passwd'}}
assert(not pcall(function()local d=N.import(old(),invalid);dofile(M.C..'/ax5/mihomo.lua').build(d)end))
local sb={outbounds={{type='anytls',tag='decorated',server='server.example',server_port=443,password='fixture'},{type='selector',tag='Native',outbounds={'decorated'},default='decorated'}},route={rules={{domain_suffix={'template.example'},outbound='Native'}},final='Native'}}
local d=N.import_singbox(old(),sb)
assert(d.route.final=='Native'and d.route.rules[#d.route.rules].domain_suffix[1]=='template.example')
assert(d.dns.servers[1].type=='fakeip')
print('native profile: strategy/rules preserved, unique identity, local override, managed ports/DNS, unsafe file refusal, sing-box full JSON passed')

policy='suffix\tgoogle.com\t分流/谷歌\nsuffix\tgstatic.com\t分流/谷歌\nsuffix\tgoogleapis.com\t分流/谷歌\n';local staleSB=old();staleSB.outbounds[#staleSB.outbounds+1]={type='selector',tag='分流/谷歌',outbounds={'removed-node'},default='removed-node'};local sbFixed=N.import_singbox(staleSB,sb);for _,g in ipairs(sbFixed.outbounds)do if g.tag=='分流/谷歌'then assert(g.default=='proxy-main')end end;assert(#sbFixed._subscription_warnings==1);print('missing fixed/local targets fall back to default proxy, staged policy remains transactional; both native formats passed')

local A=dofile(M.C..'/ax5/mihomo.lua');local modes=N.import(old(),meta());assert(A.build(modes).tun.enable==false);interception='混合模式';local runtime=A.build(modes);assert(runtime.tun.enable and runtime.tun.stack=='system'and runtime.tun['auto-route']==false);assert(runtime['proxy-groups'][1].name==modes._native_meta['proxy-groups'][1].name);print('native template cannot override managed Redir/mixed TUN; groups and rules remain intact')
