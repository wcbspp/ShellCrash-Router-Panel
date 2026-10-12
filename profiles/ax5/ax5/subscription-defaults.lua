-- Read only public subscription settings; never execute the tool configuration.
local A={}
function A.read(config,list,version)
 local cfg={}
 for line in config:gmatch('[^\r\n]+')do
  local k,v=line:match('^([%w_]+)=(.*)$')
  if k then
   if (v:sub(1,1)=="'"and v:sub(-1)=="'")or(v:sub(1,1)=='"'and v:sub(-1)=='"')then v=v:sub(2,-2)end
   cfg[k]=v
  end
 end
 local servers,templates,four={},{},0
 for line in list:gmatch('[^\r\n]+')do
  local id,name,url=line:match('^(%d%d%d)%s+(%S+)%s+(https?://%S+)')
  if id then
   local row={name=name,url=url}
   if id:match('^[34]')then servers[#servers+1]=row;if id:match('^4')then four=four+1 end
   elseif id:match('^5')then templates[#templates+1]=row end
  end
 end
 local n=tonumber(cfg.server_link)or 1;if n>four or n<1 or n%1~=0 then n=1 end
 local rule=tonumber(cfg.rule_link)or 1
 local kind,core=cfg.crashcore or'',cfg.core_v or''
 local ua=cfg.user_agent or'';local mode=(ua==''or ua=='auto')and'auto'or ua=='none'and'none'or'custom'
 if mode=='auto'then ua=kind:find('singbox',1,true)and'sing-box/singbox/'..core or kind=='meta'and'clash.meta/mihomo/'..core or'clash'
 elseif mode=='none'then ua=''end
 return {core_kind=kind,core_version=core,tool_version=version:gsub('%s+$',''),ua_mode=mode,ua=ua,
  server_index=n,converter=servers[n],template=templates[rule],include=cfg.include or'',exclude=cfg.exclude or'',
  target=kind:find('singbox',1,true)and'singbox'or'clash',parameters='insert=true · new_name=true · scv=true · udp=true'}
end
return A
