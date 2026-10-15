-- Native menu entry uses the same authenticated-local job implementation as UI.
local M=dofile('/data/ShellCrash/ax5/common.lua')
local url=arg[1]or'https://ispip.clang.cn/all_cn.txt'
local authority=url:match('^https://([^/]+)')
assert(authority and not authority:find('@',1,true)and not url:find('[%s%c#]')and #url<=2048,'rules_invalid_source')
assert(M.lock('operation.lock',900),'another operation is running')
local ok,err=pcall(function()
 local f=assert(io.open('/dev/urandom','rb'));local raw=assert(f:read(4));f:close()
 local id=raw:gsub('.',function(c)return string.format('%02x',c:byte())end);assert(#id==8)
 M.write(M.R..'/recovery-revision',tostring((tonumber(M.read(M.R..'/recovery-revision'))or 0)+1))
 M.save(M.R..'/request.json',{action='rules',args={id},rules_url=url})
 M.save(M.R..'/job.json',{active=true,phase='working',id=id,message_b64=M.b64('updating_rules')})
 require('nixio').exec('/usr/bin/lua',M.C..'/ax5/job.lua')
 error('rules job could not start')
end)
if not ok then os.remove(M.R..'/operation.lock/owner');os.remove(M.R..'/operation.lock');error(err)end
