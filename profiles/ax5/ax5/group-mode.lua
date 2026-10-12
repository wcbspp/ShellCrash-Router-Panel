local G={}
function G.apply(c,tag,mode)
 assert(mode=='auto'or mode=='manual','选择模式无效')
 local found=false
 for _,g in ipairs(c.outbounds)do if g.tag==tag and(g.type=='selector'or g.type=='urltest')then
  found=true;g.type=mode=='auto'and'urltest'or'selector';g.default=nil;g.url=nil;g.interval=nil;g.tolerance=nil;g.idle_timeout=nil
  if mode=='auto'then g.url='https://www.google.com/generate_204';g.interval='10m';g.tolerance=50 end
 end end
 assert(found and tag~='GLOBAL'and tag~='DIRECT','策略组不存在');return c
end
function G.preserve(old,new)
 local modes={};for _,g in ipairs(old)do if g.type=='urltest'then modes[g.tag]=true end end
 for _,g in ipairs(new)do if modes[g.tag]and g.type=='selector'then g.type='urltest';g.default=nil;g.url='https://www.google.com/generate_204';g.interval='10m';g.tolerance=50 end end
end
function G.layout(c)
 local nodes,regions,root={}, {},nil
 for _,g in ipairs(c.outbounds)do
  if g.server then nodes[#nodes+1]=g.tag end
  if g.tag:match('^地区/')and(g.type=='selector'or g.type=='urltest')then regions[#regions+1]=g.tag end
  if g.type=='selector'and(g.tag=='proxy-main'or g.tag=='office-anytls')then root=g end
 end
 assert(root and #nodes>0,'当前配置缺少面板默认组或节点')
 local out={};for _,g in ipairs(c.outbounds)do if g.tag~='手动选择'and g.tag~='自动选择'then out[#out+1]=g end end;c.outbounds=out
 for _,tag in ipairs(regions)do G.apply(c,tag,'auto')end
 out[#out+1]={type='selector',tag='手动选择',outbounds=nodes}
 out[#out+1]={type='urltest',tag='自动选择',outbounds=#regions>0 and regions or nodes,url='https://www.google.com/generate_204',interval='10m',tolerance=50}
 local members={'自动选择','手动选择'};for _,tag in ipairs(regions)do members[#members+1]=tag end;root.outbounds=members
 return c
end
return G
