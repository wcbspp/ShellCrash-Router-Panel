-- Stage the official tool plus exact-context adapter patches, without running upstream init.
local json=require('cjson')
local source,stage=assert(arg[1]),assert(arg[2])
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));f:close()end
local function lines(s)local t={};for l in (s..'\n'):gmatch('(.-)\n')do t[#t+1]=l end;table.remove(t);return t end
for _,name in ipairs({'init.sh','start.sh','libs/check_target.sh','libs/core_tools.sh','menus/1_start.sh','menus/9_upgrade.sh'})do
 local patch=lines(read(source..'/tool-patches/'..name:gsub('/','-')..'.patch'))
 local original=lines(read(stage..'/tool/'..name));local out,pos={},1;local i=3
 while i<=#patch do
  local begin=assert(patch[i]:match('^@@ %-(%d+)'),'Invalid patch header');begin=tonumber(begin)
  while pos<begin do out[#out+1]=assert(original[pos]);pos=pos+1 end
  i=i+1
  while i<=#patch and not patch[i]:match('^@@')do
   local marker,text=patch[i]:sub(1,1),patch[i]:sub(2)
   if marker==' 'or marker=='-'then assert(original[pos]==text,'Patch context mismatch: '..name..':'..pos);pos=pos+1 end
   if marker==' 'or marker=='+'then out[#out+1]=text end
   assert(marker==' 'or marker=='-'or marker=='+','Invalid patch line')
   i=i+1
  end
 end
 while pos<=#original do out[#out+1]=original[pos];pos=pos+1 end
 write(stage..'/tool/'..name,table.concat(out,'\n')..'\n')
end
local f=assert(io.open('/dev/urandom','rb'));local bytes=assert(f:read(24));f:close()
local secret=bytes:gsub('.',function(x)return string.format('%02x',x:byte())end)
local networks={};for line in read(source..'/examples/cn_ip.default.txt'):gmatch('[^\r\n]+')do if line:match('^%d+%.%d+%.%d+%.%d+/%d+$')then networks[#networks+1]=line end end
assert(#networks>1000,'Domestic IP baseline missing')
local cfg={log={level='warn',timestamp=true},inbounds={{type='mixed',tag='mixed-in',listen='127.0.0.1',listen_port=7890},{type='redirect',tag='redirect-in',listen='0.0.0.0',listen_port=7892},{type='direct',tag='dns-in',listen='0.0.0.0',listen_port=1053}},
 outbounds={{type='selector',tag='proxy-main',outbounds={'direct'},default='direct'},{type='direct',tag='direct',routing_mark=21315},{type='selector',tag='DIRECT',outbounds={'direct'}},{type='selector',tag='GLOBAL',outbounds={'proxy-main'}}},
 dns={servers={{type='udp',tag='dns-direct',server='223.5.5.5'},{type='tcp',tag='dns-proxy',server='8.8.8.8',detour='proxy-main'}},rules={{rule_set={'cn'},server='dns-direct'}},strategy='ipv4_only',final='dns-direct'},
 route={default_mark=21315,default_domain_resolver='dns-direct',rule_set={{type='local',tag='cn',format='binary',path='/data/ShellCrash/ruleset/cn.srs'}},rules={{inbound={'dns-in'},action='hijack-dns'},{ip_is_private=true,outbound='direct'},{rule_set={'cn'},outbound='direct'},{ip_cidr=networks,outbound='direct'}},final='proxy-main'},
 experimental={clash_api={external_controller='127.0.0.1:9999',secret=secret},cache_file={enabled=true,path='/tmp/ShellCrash/fakeip.db',store_fakeip=true}}}
write(stage..'/panel/configs/config.json',json.encode(cfg))
write(stage..'/panel/configs/api-header','Authorization: Bearer '..secret..'\n')
write(stage..'/panel/configs/enabled','1\n')
write(stage..'/panel/configs/dns-mode','redir_host\n')
write(stage..'/panel/configs/fake_ip_filter.list','# LAN\n+.lan\n+.local\n+.home.arpa\n')
write(stage..'/panel/configs/needs-subscription','1\n')
write(stage..'/tool/configs/ShellCrash.cfg',"crashcore=singbox\ncore_v=1.12.13\ncpucore=armv7\nzip_type=tar.gz\ndisoverride=0\nuserguide=1\ndns_mod=redir_host\nrelease_type=1.9.4\nurl_id=102\n")
write(stage..'/tool/configs/command.env','BINDIR=/data/ShellCrash\nTMPDIR=/tmp/ShellCrash\n')

