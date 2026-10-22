-- Bounded DHCP/neighbour inventory. Never treat a lease as proof of reachability.
local json=require('cjson')
local root=arg[2]or'/etc/storage/ShellCrash'
local function read(path)local f=io.open(path,'rb');if not f then return ''end;local s=f:read(65536)or'';f:close();return s end
local function mac(s)
 s=(s or''):lower();if not s:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$')or s=='00:00:00:00:00:00'or tonumber(s:sub(1,2),16)%2~=0 then return nil end;return s
end
local function ip(s)
 if type(s)~='string'then return nil end
 local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$');if not a then return nil end
 for _,v in ipairs({a,b,c,d})do if #v>3 or tonumber(v)>255 or(#v>1 and v:sub(1,1)=='0')then return nil end end
 if tonumber(a)==0 or tonumber(a)==127 or tonumber(a)>=224 then return nil end;return s
end
local rows,byip,leaseNames={},{},{}
local function add(address,hardware,name,state)
 address,hardware=ip(address),mac(hardware);if not address or not hardware then return end
 local row=byip[address]
 if not row then if #rows>=256 then return end;row={ip=address,mac=hardware,name='',status='recent'};rows[#rows+1]=row;byip[address]=row end
 name=name or leaseNames[address..'|'..hardware]
 row.mac=hardware;if name and name~='*'then row.name=name:sub(1,128)end;if state then row.status=state end
end
for _,path in ipairs({'/tmp/dhcp.leases','/tmp/dnsmasq.leases','/var/lib/dhcp/dhcpd.leases','/var/lib/dhcpd/dhcpd.leases'})do
 for line in read(path):gmatch('[^\r\n]+')do local expiry,m,a,n=line:match('^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)');if expiry then local address,hardware=ip(a),mac(m);if address and hardware and n~='*'then leaseNames[address..'|'..hardware]=n end;if tonumber(expiry)==0 or tonumber(expiry)>os.time()then add(a,m,n,'lease')end end end
end
local lan=root:match('^/data/')and'br-lan'or'br0'
for line in read('/proc/net/arp'):gmatch('[^\r\n]+')do
 local a,flags,m,dev=line:match('^(%S+)%s+%S+%s+(%S+)%s+(%S+)%s+%S+%s+(%S+)');if dev==lan and flags=='0x2'then add(a,m,nil,'recent')end
end
local p=io.popen('ip neigh show dev '..lan..' 2>/dev/null')
if p then local text=p:read(65536)or'';p:close();for line in text:gmatch('[^\r\n]+')do local a,m,state=line:match('^(%S+).*lladdr%s+(%S+)%s+(%u+)');if state=='REACHABLE'or state=='DELAY'or state=='PROBE'then add(a,m,nil,'online')end end end
if arg[1]=='resolve'then
 local text=read(assert(arg[3]));local first=text:match('^([^\n]+)');assert(first=='0'or first=='1','invalid switch')
 local out,seen={first},{}
 for entry in text:gmatch('[^\r\n]+')do if entry~=first then local key=mac(entry)or(byip[entry]and byip[entry].mac)or ip(entry);assert(key,'invalid address');if not seen[key]then seen[key]=true;out[#out+1]=key end end end
 assert(#out<=65 and(first=='0'or #out>1),'empty or oversized whitelist')
 local f=assert(io.open(assert(arg[4]),'wb'));f:write(table.concat(out,'\n')..'\n');f:close()
else table.sort(rows,function(a,b)return a.ip<b.ip end);if #rows==0 then print('{"devices":[],"generated_at":'..os.time()..'}')else print(json.encode({devices=rows,generated_at=os.time()}))end end
