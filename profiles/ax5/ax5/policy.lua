local P={}
P.presets={
 {tag='分流/谷歌',domains={'google.com','gstatic.com','googleapis.com'}},
 {tag='分流/ChatGPT',domains={'chatgpt.com','openai.com','oaistatic.com','oaiusercontent.com'}},
 {tag='分流/国外 AI',domains={'claude.ai','anthropic.com','perplexity.ai','poe.com'}},
 {tag='分流/GitHub',domains={'github.com','githubusercontent.com','githubassets.com'}}
}
-- Only local overrides may fall back. Invalid upstream rules still fail validation.
function P.reconcile(c,text)
 local known={};for _,o in ipairs(c.outbounds or{})do known[o.tag]=o end
 assert(known['proxy-main'],'缺少默认代理，当前配置保留')
 local warnings=c._subscription_warnings or{};c._subscription_warnings=warnings
 local members={};for _,o in ipairs(c.outbounds or{})do if not o.tag:match('^分流/')and o.tag~='GLOBAL'and o.tag~='DIRECT'and(o.server or o.type=='selector'or o.type=='urltest'or o.type=='direct')then members[#members+1]=o.tag end end
 for _,o in ipairs(c.outbounds or{})do
  if o.tag:match('^分流/')then
   o.outbounds=members
   if o.default and not known[o.default]then
    warnings[#warnings+1]=o.tag..'：'..o.default..' 不在新订阅中，已重置为默认代理'
    o.default='proxy-main'
   end
  end
 end
 local lines={};for line in text:gmatch('[^\n]+')do
  local prefix,target=line:match('^(.*\t)([^\t]+)$')
  if target and not known[target]then
   warnings[#warnings+1]=target..' 不在新订阅中，域名分流已重置为默认代理'
   for _,r in ipairs(c.route and c.route.rules or{})do if r.outbound==target then r.outbound='proxy-main' end end
   line=prefix..'proxy-main'
  end
  lines[#lines+1]=line
 end
 return #lines>0 and table.concat(lines,'\n')..'\n'or''
end
-- Stable rule targets let native Selector changes bypass config validation/restart.
function P.groups(c,rows)
 local members,known={},{}
 for _,o in ipairs(c.outbounds or{})do
  known[o.tag]=o
  if not o.tag:match('^分流/')and o.tag~='GLOBAL'and o.tag~='DIRECT'and(o.type=='selector'or o.type=='urltest'or o.type=='direct'or o.server)then members[#members+1]=o.tag end
 end
 for _,p in ipairs(P.presets)do
  local matches={};local target
  for _,r in ipairs(rows)do
   if r.domain_suffix and #r.domain_suffix==1 then for _,d in ipairs(p.domains)do if r.domain_suffix[1]==d then matches[#matches+1]=r;target=target or r.outbound;assert(target==r.outbound,'同一快捷分流的域名需要选择同一目标')end end end
  end
  if #matches==#p.domains then
   if target~=p.tag then
    assert(not target:match('^分流/'),'分流组不能互相引用')
    if not known[p.tag]then local g={type='selector',tag=p.tag,outbounds=members,default=target};c.outbounds[#c.outbounds+1]=g;known[p.tag]=g
    else known[p.tag].outbounds=members;known[p.tag].default=target end
   elseif known[p.tag]then known[p.tag].outbounds=members
   else error('分流策略组缺失')end
   for _,r in ipairs(matches)do r.outbound=p.tag end
  end
 end
 return rows
end
function P.text(rows)
 local lines={};for _,r in ipairs(rows)do lines[#lines+1]=(r.domain and'exact'or'suffix')..'\t'..(r.domain or r.domain_suffix)[1]..'\t'..r.outbound end
 return #lines>0 and table.concat(lines,'\n')..'\n'or''
end
function P.parse(text,c)
 assert(type(text)=='string'and #text<=12000,'分流规则内容过大')
 local groups={direct=true};for _,o in ipairs(c.outbounds or{})do if o.type=='selector'or o.type=='urltest'or o.server then groups[o.tag]=true end end
 local rows,seen={},{}
 for line in text:gmatch('[^\n]+')do
  local kind,domain,target=line:match('^(%a+)\t([^\t]+)\t([^\t]+)$')
  assert((kind=='exact'or kind=='suffix')and #domain<=253 and domain:match('^[a-z0-9%.%-]+$')and domain:find('.',1,true)and not domain:find('..',1,true),'域名格式无效，请填写域名，不含网址或通配符')
  for part in domain:gmatch('[^.]+')do assert(#part<=63 and part:match('^[a-z0-9]')and part:match('[a-z0-9]$'),'域名格式无效')end
  assert(not domain:match('^%.')and not domain:match('%.$')and groups[target]and target~='GLOBAL'and target~='DIRECT','目标组或节点不存在，请重新选择')
  assert(not seen[kind..':'..domain],'规则重复');seen[kind..':'..domain]=true
  rows[#rows+1]={[kind=='exact'and'domain'or'domain_suffix']={domain},outbound=target};assert(#rows<=32,'最多添加 32 条简单分流规则')
 end
 return rows
end
function P.apply(c,new,old)
 local previous={};for _,r in ipairs(old)do previous[(r.domain and'exact'or'suffix')..':'..(r.domain or r.domain_suffix)[1]..':'..r.outbound]=true end
 local safe,rest={},{}
 for _,r in ipairs(c.route.rules or{})do
  local d=r.domain or r.domain_suffix;local key=d and #d==1 and ((r.domain and'exact'or'suffix')..':'..d[1]..':'..(r.outbound or''))
  local keys=0;for _ in pairs(r)do keys=keys+1 end
  if not(key and keys==2 and previous[key])then
   if r.action=='hijack-dns'or r.action=='sniff'or r.ip_is_private then safe[#safe+1]=r else rest[#rest+1]=r end
  end
 end
 for _,r in ipairs(new)do safe[#safe+1]=r end;for _,r in ipairs(rest)do safe[#safe+1]=r end;c.route.rules=safe;return c
end
return P
