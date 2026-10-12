local p='/usr/lib/lua/luci/view/web/inc/header.htm'
local f=assert(io.open(p));local s=f:read('*a');f:close()
if s:find('build_url("web","shellcrash")',1,true)then return end
local link='<li><a href="<%=luci.dispatcher.build_url("web","shellcrash")%>">ShellCrash</a></li>\n'
local count=0
s=s:gsub('(<ul>)(.-)(</ul>)',function(a,b,c)count=count+1;return a..b..link..c end)
assert(count>0,'Unsupported Xiaomi menu structure; header preserved')
f=assert(io.open(p..'.new','w'));assert(f:write(s));f:close();assert(os.rename(p..'.new',p))
