-- Reload only the local domestic fallback; never replace subscription providers.
local A={}
function A.apply(M,text,count)
 local path=M.C..'/configs/cn_ip.txt';local old=M.read(path)
 if old==text then return false end
 local function replace(data)
  M.write(path..'.new',data);assert(os.rename(path..'.new',path),'国内 IP 表写入失败')
 end
 local function reload(expected)
  local _,code=M.request('/providers/rules/panel-cn-ip','PUT','')
  assert(code>=200 and code<300,'国内 IP 表加载失败')
  local raw,status=M.request('/providers/rules');assert(status==200,'国内 IP 表读回失败')
  local d=M.json.decode(raw);local p=d.providers and d.providers['panel-cn-ip']
  assert(p and p.vehicleType=='File'and tonumber(p.ruleCount)==expected,'国内 IP 表加载条目数不一致')
 end
 replace(text)
 local ok,err=pcall(reload,count)
 if not ok then
  replace(old);local previous=0;for _ in old:gmatch('[^\r\n]+')do previous=previous+1 end
  local restored=pcall(reload,previous)
  error(restored and '国内 IP 表加载失败，已恢复旧规则' or '国内 IP 旧文件已恢复，内核加载状态待确认',0)
 end
 return true
end
return A
