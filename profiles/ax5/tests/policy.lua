local P=dofile(arg[1]or'/data/ShellCrash/ax5/policy.lua')
local c={outbounds={{type='selector',tag='地区/台湾'},{type='direct',tag='direct'}},route={rules={{rule_set={'cn'},outbound='direct'},{action='hijack-dns',inbound='dns-in'},{ip_is_private=true,outbound='direct'}},final='proxy-main'}}
local rows=P.parse('suffix\tgithub.com\t地区/台湾\n',c);P.apply(c,rows,{})
assert(c.route.rules[1].action=='hijack-dns'and c.route.rules[2].ip_is_private and c.route.rules[3].domain_suffix[1]=='github.com'and c.route.rules[4].rule_set[1]=='cn')
local next=P.parse('exact\tapi.example.com\tdirect\n',c);P.apply(c,next,rows);assert(#c.route.rules==4 and c.route.rules[3].domain[1]=='api.example.com')
P.apply(c,{},next);assert(#c.route.rules==3 and c.route.final=='proxy-main')
for _,t in ipairs({'suffix\thttps://x.com\tdirect\n','exact\tx.com\tmissing\n','exact\t-abc.com\tdirect\n','suffix\t*.test.com\tdirect\n','suffix\tx.com\tdirect\nsuffix\tx.com\tdirect\n'})do assert(not pcall(P.parse,t,c))end
print('domain policy parse, preservation, precedence, replacement, removal and validation passed')
local x={outbounds={{type='selector',tag='root',outbounds={'node'}},{type='direct',tag='direct'},{type='trojan',tag='node',server='example.com'}},route={rules={},final='root'}}
local r=P.parse('suffix\tgoogle.com\tnode\nsuffix\tgstatic.com\tnode\nsuffix\tgoogleapis.com\tnode\n',x)
P.groups(x,r);assert(#x.outbounds==4 and x.outbounds[4].tag=='分流/谷歌'and x.outbounds[4].default=='node')
for _,v in ipairs(x.outbounds[4].outbounds)do assert(not v:match('^分流/'))end
P.apply(x,r,{});local text=P.text(r);assert(text:find('分流/谷歌',1,true));local next=P.parse(text,x);P.groups(x,next);assert(#x.outbounds==4);P.apply(x,next,r);assert(#x.route.rules==3)
print('stable preset groups, migration, reference preservation and idempotence passed')
