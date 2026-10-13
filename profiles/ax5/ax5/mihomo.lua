local M=dofile('/data/ShellCrash/ax5/common.lua')
local A={}
function A.build(c)
 if c._native_meta then
  local skeleton={};for k,v in pairs(c)do if k~='_native_meta'then skeleton[k]=v end end
  skeleton.outbounds={};for _,o in ipairs(c.outbounds)do if not o.server then skeleton.outbounds[#skeleton.outbounds+1]=o end end
  return dofile(M.C..'/ax5/native-profile.lua').merge(c,A.build(skeleton))
 end
 local ps,gs={},{}
 for _,o in ipairs(c.outbounds)do
  if o.type=='selector'or o.type=='urltest'then
   if o.tag~='DIRECT'and o.tag~='GLOBAL'then
    local names={};if o.type=='selector'and o.default then names[#names+1]=o.default=='direct'and'DIRECT'or o.default end;for _,n in ipairs(o.outbounds)do if o.type~='selector'or n~=o.default then names[#names+1]=n=='direct'and'DIRECT'or n end end
    local g={name=o.tag,type=o.type=='urltest'and'url-test'or'select',proxies=names};if o.type=='urltest'then g.url=o.url or'https://www.google.com/generate_204';g.interval=600;g.tolerance=50;g.lazy=true end;gs[#gs+1]=g
   end
  elseif o.type=='direct'or o.type=='block'then
  else
   local t=o.type;local tls=o.tls or{};local p={name=o.tag,type=t,server=o.server,port=o.server_port,udp=o.network~="tcp"}
   if t=='anytls'or t=='trojan'then p.password=o.password
   elseif t=='shadowsocks'then
    p.type='ss';p.cipher=o.method;p.password=o.password
    if o.plugin and o.plugin~=''then
     if o.plugin~='obfs-local'then error('当前适配未支持 SS 插件：'..o.plugin)end
     local opts={};for k,v in (o.plugin_opts or''):gmatch('([^=;]+)=([^;]*)')do opts[k]=v end
     if opts.obfs~='http'and opts.obfs~='tls'then error('SS 混淆模式无效')end
     p.plugin='obfs';p['plugin-opts']={mode=opts.obfs,host=opts['obfs-host']or o.server}
    end
   elseif t=='shadowsocksr'then
    p.type='ssr';p.cipher=o.method;p.password=o.password;p.protocol=o.protocol;p.obfs=o.obfs;p['protocol-param']=o.protocol_param;p['obfs-param']=o.obfs_param
   elseif t=='vmess'or t=='vless'then p.uuid=o.uuid;p.alterId=o.alter_id or 0;p.cipher=o.security or'auto';p.tls=tls.enabled or false;p.flow=o.flow
   else error('该节点协议暂无 AX5 跨内核转换：'..t)end
   p.sni=tls.server_name or o.server;p['skip-cert-verify']=tls.insecure or false;p.alpn=tls.alpn
   if o.transport then
    local v=o.transport;if v.type=='ws'then p.network='ws';p['ws-opts']={path=v.path,headers=v.headers}
    elseif v.type=='grpc'then p.network='grpc';p['grpc-opts']={['grpc-service-name']=v.service_name}
    else error('该节点传输暂无 AX5 跨内核转换：'..v.type)end
   end
   ps[#ps+1]=p
  end
 end
 gs[#gs+1]={name='direct',type='select',proxies={'DIRECT'}}
 local rules={};for _,n in ipairs({'0.0.0.0/8','10.0.0.0/8','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.168.0.0/16','224.0.0.0/4','240.0.0.0/4'})do rules[#rules+1]='IP-CIDR,'..n..',DIRECT,no-resolve'end
 for _,r in ipairs(c.route.rules)do
  if r.outbound and (r.domain or r.domain_suffix)then
   local target=r.outbound=='direct'and'DIRECT'or r.outbound
   for _,d in ipairs(r.domain or{})do rules[#rules+1]='DOMAIN,'..d..','..target end
   for _,d in ipairs(r.domain_suffix or{})do rules[#rules+1]='DOMAIN-SUFFIX,'..d..','..target end
  end
 end
 rules[#rules+1]='RULE-SET,cn,DIRECT'
 for _,r in ipairs(c.route.rules)do if r.ip_cidr and #r.ip_cidr>1000 then for _,n in ipairs(r.ip_cidr)do rules[#rules+1]='IP-CIDR,'..n..',DIRECT,no-resolve'end end end
 rules[#rules+1]='MATCH,proxy-main'
 local filter={'rule-set:cn'};for line in M.read(M.C..'/configs/fake_ip_filter.list'):gmatch('[^\r\n]+')do line=line:match('^%s*(.-)%s*$');if line~=''and not line:match('^#')and not line:find(' ')then filter[#filter+1]=line end end
 local mode='redir_host';for _,server in ipairs(c.dns.servers or{})do if server.type=='fakeip'then mode='mix'end end
 local hosts={};for line in M.read(M.R..'/hosts'):gmatch('[^\n]+')do local ip,n=line:match('^(%d+%.%d+%.%d+%.%d+)%s+([^%s#]+)');if ip and n then hosts[n]=ip end end
 return {tun=dofile(M.C..'/ax5/transport-mode.lua').tun(),['mixed-port']=7890,['redir-port']=7892,['allow-lan']=true,['bind-address']='*',mode='rule',['log-level']='warning',ipv6=false,['routing-mark']=21315,['find-process-mode']='off',['external-controller']='127.0.0.1:9999',secret=c.experimental.clash_api.secret,['geo-auto-update']=false,profile={['store-selected']=false,['store-fake-ip']=true},hosts=hosts,proxies=ps,['proxy-groups']=gs,['rule-providers']={cn={type='file',behavior='domain',format='mrs',path='/data/ShellCrash/ruleset/cn.mrs'}},dns={enable=true,listen='0.0.0.0:1053',ipv6=false,['enhanced-mode']=mode=='mix'and'fake-ip'or'redir-host',['fake-ip-range']='198.18.0.1/15',['fake-ip-filter']=filter,['default-nameserver']={'223.5.5.5'},nameserver={'tcp://8.8.8.8#proxy-main','https://cloudflare-dns.com/dns-query#proxy-main'},['nameserver-policy']={['rule-set:cn']={'223.5.5.5'},['+.lan']={'223.5.5.5'},['+.local']={'223.5.5.5'}},['proxy-server-nameserver']={'223.5.5.5'},['direct-nameserver']={'223.5.5.5'}},rules=rules}
end
if arg and arg[1]=='generate'then M.write(arg[3] or M.C..'/configs/config.yaml',M.encode(A.build(M.load(arg[2] or M.C..'/configs/config.json'))):gsub('\\/','/'))end
return A
