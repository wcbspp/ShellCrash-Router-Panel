local N={}
-- Conversion services decorate names. Keep names only for an unambiguous
-- match of protocol, endpoint and authentication; never match by display name.
local function key(n)
 if not n.server then return nil end
 local fields={'type','server','server_port','password','uuid','method','protocol','protocol_param','obfs','obfs_param'}
 local parts={};for _,f in ipairs(fields)do local v=tostring(n[f]or'');parts[#parts+1]=#v..':'..v end
 return table.concat(parts,'|')
end
function N.preserve(old,new)
 local prior,counts,used={},{},{}
 for _,n in ipairs(old or{})do local k=key(n);if k then counts[k]=(counts[k]or 0)+1;prior[k]=n.tag end end
 local incoming={};for _,n in ipairs(new)do local k=key(n);if k then incoming[k]=(incoming[k]or 0)+1 end;used[n.tag]=true end
 local renamed={}
 for _,n in ipairs(new)do
  local k=key(n);local tag=k and counts[k]==1 and incoming[k]==1 and prior[k]
  if tag and tag~=n.tag and not used[tag]then renamed[n.tag]=tag;used[tag]=true;n.tag=tag end
 end
 for _,n in ipairs(new)do
  if n.outbounds then for i,tag in ipairs(n.outbounds)do n.outbounds[i]=renamed[tag]or tag end end
  if n.default then n.default=renamed[n.default]or n.default end
  if n.detour then n.detour=renamed[n.detour]or n.detour end
 end
 return new,renamed
end
function N.validate_targets(c)
 local available={};for _,n in ipairs(c.outbounds or{})do available[n.tag]=true end
 for _,n in ipairs(c.outbounds or{})do
  if n.default and not available[n.default]then error('订阅未提供策略组“'..n.tag..'”的固定节点“'..n.default..'”；当前配置保留',0)end
  for _,tag in ipairs(n.outbounds or{})do if not available[tag]then error('订阅未提供策略组“'..n.tag..'”的成员“'..tag..'”；当前配置保留',0)end end
 end
 for _,r in ipairs(c.route.rules or{})do
  if r.outbound and not available[r.outbound]then error('订阅未提供分流目标“'..r.outbound..'”；请先重新选择该域名的分流目标，当前配置保留',0)end
 end
end
return N
