local A={}
function A.warning(c,policy,mode)
 if mode=='fake-ip'then return 'fakeip'end
 for line in (policy or''):gmatch('[^\n]+')do if line:match('\t([^\t]+)$')~='direct'then return 'policy'end end
 if c._native_meta then
  for _,r in ipairs(c._native_meta.rules or{})do
   if r:match('^MATCH,REJECT')then return 'rules'end
   if not r:match('^MATCH,')then
    local target=r:match(',([^,]+),no%-resolve$')or r:match(',([^,]+)$')
    if target~='DIRECT'and target~='direct'then return 'rules'end
   end
  end
 else
  local valid=false;for _,o in ipairs(c.outbounds or{})do if o.type=='direct'and o.tag=='direct'then valid=true end end
  if not valid then return 'rules'end
  for _,r in ipairs(c.route and c.route.rules or{})do
   local terminal=r.outbound~=nil and(not r.action or r.action=='route')
   for k in pairs(r)do if k~='outbound'and k~='action'and k~='type'then terminal=false end end
   local guard=r.clash_mode=='Global'or r.clash_mode=='Direct'
   if guard then for k in pairs(r)do if k~='clash_mode'and k~='outbound'and k~='action'then guard=false end end end
   local direct=not r.rules and r.outbound=='direct'and(not r.action or r.action=='route')
   local dns=not r.rules and(r.action=='sniff'or r.action=='hijack-dns')
   if not(guard or terminal or direct or dns)then return 'rules'end
  end
 end
 return 'ready'
end
function A.check(c,policy,mode)
 if mode=='fake-ip'then return 'fakeip'end
 if not c._native_meta then
  local direct=false;for _,o in ipairs(c.outbounds or{})do if o.type=='direct'and o.tag=='direct'then direct=true end end
  if not direct or type(c.route)~='table'then return 'invalid'end
 end
 return 'ready'
end
function A.state(M,index)
 local enabled=M.read(M.C..'/configs/cn-bypass'):match('^1')~=nil
 local d=M.load(M.R..'/cn-state.json');d.enabled=enabled;d.available=index.cn_eligible=='ready';d.reason=enabled and(d.reason or'pending')or(index.cn_eligible~='ready'and index.cn_eligible or'disabled');d.warning=index.cn_warning~='ready'and index.cn_warning or nil;d.active=enabled and d.active==true and M.pid()>0;if enabled and M.pid()==0 then d.reason='stopped'end
 return d
end
function A.apply(M,value)
 assert(value=='0'or value=='1','invalid_bypass')
 local old=M.read(M.C..'/configs/cn-bypass');local state=M.state()
 if value=='1'then assert(state.running,'内核未运行');assert(state.cn_bypass.available,'当前分流规则与国内 IP 绕过冲突，设置未变')end
 local mode='unknown'
 if state.running then local raw,status=M.request('/configs');if status==200 then mode=tostring(M.json.decode(raw).mode):lower()end end
 if value=='1'then assert(({rule=true,direct=true,global=true})[mode],'core_unavailable')end
 local tool='/data/ShellCrash-tool';local prior=M.read(tool..'/configs/ShellCrash.cfg'):match('cn_ip_route=([^\n]+)')
 local function set(value)
  return M.run('CRASHDIR='..M.quote(tool)..' sh -c '..M.quote('. "$CRASHDIR/libs/set_config.sh"; setconfig cn_ip_route '..M.quote(value)))
 end
 assert(set(value=='1'and'ON'or'OFF'),'ShellCrash 设置保存失败')
 local path=M.C..'/configs/cn-bypass';M.write(path,value..'\n')
 local ok=M.run('SC_CN_FLOW_MODE='..M.quote(mode)..' '..M.C..'/ax5/cn-bypass.sh apply')
 local after=M.load(M.R..'/cn-state.json')
 if not ok or(value=='1'and mode=='rule'and not after.active)then
  if prior then set(prior)else M.run('sed -i '..M.quote('/^cn_ip_route=/d')..' '..tool..'/configs/ShellCrash.cfg')end
  if old==''then os.remove(path)else M.write(path,old)end;M.run('SC_CN_FLOW_MODE='..M.quote(mode)..' '..M.C..'/ax5/cn-bypass.sh apply');error('国内 IP 绕过未通过验证，已尝试恢复原设置')
 end
 return true
end
return A

