-- Consume a decompressed single-core tar stream. Never execute its contents.
local output, receipt = assert(arg[1]), assert(arg[2])
local cap, reserve = 33554432, 24576
local function exact(n)
 local s=io.stdin:read(n); assert(s and #s==n,'truncated core tar'); return s
end
local h=exact(512)
local function octal(s)
 s=s:gsub('%z.*$',''):match('^%s*(.-)%s*$')
 assert(s:match('^[0-7]+$'),'invalid tar number'); return assert(tonumber(s,8))
end
assert(h:sub(1,100):gsub('%z.*$','')=='CrashCore','unexpected core entry')
assert(h:sub(157,157)=='0' or h:sub(157,157)=='\0','nonregular core entry')
assert(h:sub(158,257):gsub('%z.*$','')=='','linked core entry')
assert(h:sub(346,500):gsub('%z.*$','')=='','prefixed core entry')
local sum=0
for i=1,512 do sum=sum+((i>=149 and i<=156) and 32 or h:byte(i)) end
assert(sum==octal(h:sub(149,156)),'invalid tar checksum')
local size=octal(h:sub(125,136)); assert(size>=1000000 and size<=cap,'invalid core size')
local mem=assert(io.open('/proc/meminfo')):read('*a')
local available=tonumber(mem:match('MemAvailable:%s+(%d+)') or mem:match('MemFree:%s+(%d+)'))
local required=math.ceil(size/1024)+reserve
if not available or available<required then
 io.stderr:write('core_memory_insufficient available_kib=',tostring(available),
                 ' required_kib=',required,' reserve_kib=',reserve,'\n')
 error('core_memory_insufficient')
end
local f=assert(io.open(output,'wb')); local remaining=size
while remaining>0 do
 local s=exact(math.min(65536,remaining)); assert(f:write(s)); remaining=remaining-#s
end
assert(f:close())
local padding=(512-size%512)%512
if padding>0 then assert(exact(padding)==string.rep('\0',padding),'invalid tar padding') end
local tail=0
while true do
 local s=io.stdin:read(4096); if not s then break end
 tail=tail+#s; assert(tail<=65536 and not s:find('[^%z]'),'unexpected trailing tar member')
end
assert(tail>=1024 and tail%512==0,'missing tar end markers')
local r=assert(io.open(receipt,'w')); assert(r:write('binary_size=',size,'\n')); assert(r:close())
