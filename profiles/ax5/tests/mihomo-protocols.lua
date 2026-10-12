local original=dofile;dofile=function()return {C='/persist',R='/ram',read=function()return ''end}end
local A=original(arg[1]or'/data/ShellCrash/ax5/mihomo.lua');dofile=original
local function cfg(n)return {outbounds={n},route={rules={}},dns={servers={}},experimental={clash_api={secret='fixture'}}}end
local n={type='shadowsocks',tag='fixture',server='node.example.com',server_port=443,method='chacha20-ietf',password='fixture',plugin='obfs-local',plugin_opts='obfs=http;obfs-host=host.example.com'}
local p=A.build(cfg(n)).proxies[1];assert(p.plugin=='obfs'and p['plugin-opts'].mode=='http'and p['plugin-opts'].host=='host.example.com')
n.plugin='unknown-plugin';assert(not pcall(A.build,cfg(n)))
n={type='shadowsocksr',tag='fixture',server='node.example.com',server_port=443,method='chacha20-ietf',password='fixture',protocol='auth_aes128_sha1',obfs='tls1.2_ticket_auth',obfs_param='host.example.com'}
p=A.build(cfg(n)).proxies[1];assert(p.type=='ssr'and p.protocol==n.protocol and p['obfs-param']==n.obfs_param)
print('mihomo protocols: 3 cases passed')
