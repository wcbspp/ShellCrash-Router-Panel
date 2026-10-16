local M=dofile('/data/ShellCrash/ax5/common.lua')
local wanted=arg[1]or''
if not wanted:match('^%d+$')or #wanted>10 then os.exit(1)end
local function key(name)local h=0;for i=1,#name do h=(h*131+name:byte(i))%2147483647 end;return string.format('%.0f',h)end
local count,host,detour=0,nil,nil
local parsed=dofile(M.C..'/ax5/inspect.lua').each_object(M.C..'/configs/config.json','outbounds',function(n)
 if type(n.tag)=='string'and key(n.tag)==wanted then count=count+1;host=n.server;detour=n.detour end
end,nil,true)
if not parsed or count~=1 or type(host)~='string'or #host>253 or not host:match('^[%w][%w%.%-]*$')or host:find('..',1,true)or host:sub(-1)=='.'or(detour and detour~='')then os.exit(1)end
io.write(host,'\n')
