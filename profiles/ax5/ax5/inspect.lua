local M=dofile('/data/ShellCrash/ax5/common.lua')
local I={}
-- Parse one JSON object at a time from the kernel's top-level array response.
-- Keeping the full rules response as Lua tables costs several MB on AX5.
function I.each_object(path,key,visit,map)
 local f=io.open(path,'rb');if not f then return false end
 local prefix,started,finished='',false,false
 local depth,in_string,escaped=0,false,false
 local pieces,size,n={},0,0
 local key_phase,key_parts,key_escaped,member_key='key',{},false,nil
 local function abort()f:close();return false end
 while true do
  local block=f:read(4096);if not block then break end
  for pos=1,#block do
   local ch=block:sub(pos,pos)
   if not started then
    prefix=prefix..ch
    if prefix:match('"'..key..'"%s*:%s*'..(map and '%{'or'%[')..'$')then started=true;prefix=''elseif #prefix>8192 then return abort()end
   elseif depth==0 then
    if map and key_phase=='string'then
     key_parts[#key_parts+1]=ch;if #key_parts>1024 then return abort()end
     if key_escaped then key_escaped=false elseif ch=='\\'then key_escaped=true elseif ch=='"'then
      local ok,name=pcall(M.json.decode,table.concat(key_parts));if not ok or type(name)~='string'then return abort()end
      member_key=name;key_parts={};key_phase='colon'
     end
    elseif map and key_phase=='key'then
     if ch=='}'then finished=true;break elseif ch=='"'then key_parts={'"'};key_phase='string';key_escaped=false
     elseif not ch:match('[%s,]')then return abort()end
    elseif map and key_phase=='colon'then
     if ch==':'then key_phase='value'elseif not ch:match('%s')then return abort()end
    elseif not map and ch==']'then finished=true;break
    elseif ch=='{'then depth=1;pieces={'{'};size=1;in_string=false;escaped=false
    elseif not ch:match('[%s,]')then return abort()end
   else
    size=size+1;if size>16384 then return abort()end;pieces[#pieces+1]=ch
    if in_string then
     if escaped then escaped=false elseif ch=='\\'then escaped=true elseif ch=='"'then in_string=false end
    elseif ch=='"'then in_string=true
    elseif ch=='{'then depth=depth+1
    elseif ch=='}'then
     depth=depth-1
     if depth==0 then
      local ok,obj=pcall(M.json.decode,table.concat(pieces));pieces={};if not ok then return abort()end
      n=n+1;visit(obj,n,member_key);key_phase='key';if n%50==0 then collectgarbage('collect')end
     end
    end
   end
  end
  if finished then break end
 end
 f:close();collectgarbage('collect');return started and finished and depth==0
end

local function query(view,page,q)
 local paths={rules='/rules',groups='/proxies',connections='/connections'}
 if not paths[view] or #q>128 or not page or page<0 or page>10000 or page~=math.floor(page)then return nil,'查询参数无效',400 end
 if M.load(M.R..'/job.json').active then return nil,'正在处理配置，请稍后查询',503 end
 if M.pid()==0 then return nil,'代理已停止，启动后可查询运行数据',503 end
 -- Streaming retains one object and at most 20 rows; no full proxy-table clone.
 local mem=M.memory();local available=mem.MemAvailable or mem.MemFree or 0;local reserve=M.limits().protect_mb+2
 if available<reserve*1024 then return nil,string.format('内存余量不足，暂缓查询（当前 %.1f MB；查询至少需要 %d MB）',available/1024,reserve),503 end
 local path=M.R..'/inspect-'..require('nixio').getpid()..'.json'
 local ok,code=dofile(M.C..'/ax5/core-stream.lua').fetch(paths[view],path,1048576)
 if not ok then os.remove(path);return nil,code==413 and '数据超过轻量查询的 1 MB 上限，请在高级面板查看' or '内核查询失败，请稍后重试',code or 502 end
 local rows={};local total=0;local first=page*20;local query=q:lower()
 local function add(title,detail,order)
  title=tostring(title or'—');detail=tostring(detail or'')
  if not (title..' '..detail):lower():find(query,1,true)then return end
  total=total+1;if total>first and total<=first+20 then rows[#rows+1]={title=title,detail=detail,order=order}end
 end
 local valid=true
 if view=='rules'then
  valid=I.each_object(path,'rules',function(r,n)add(r.payload or r.rule or r.ruleSet or r.type,(r.type or'')..' → '..(r.proxy or r.outbound or''),n)end)
 elseif view=='groups'then
  local groups={}
  valid=I.each_object(path,'proxies',function(p,_,name)
   if type(p.all)=='table'then groups[#groups+1]={name=name,kind=p.type,count=#p.all,now=p.now}end
  end,true)
  table.sort(groups,function(a,b)return a.name<b.name end)
  for _,p in ipairs(groups)do add(p.name,(p.kind or'策略组')..' · '..p.count..' 个成员 · 当前 '..(p.now or'未选择'))end
 else
  valid=I.each_object(path,'connections',function(c)
   local m=c.metadata or{};local bits={m.network or'',m.sourceIP and(m.sourceIP..':'..tostring(m.sourcePort or''))or'',table.concat(c.chains or{},' → '),c.rule and(c.rule..(c.rulePayload and(' / '..c.rulePayload)or''))or''};add(m.host or m.destinationIP or'未知目标',table.concat(bits,' · '))
  end)
 end
 os.remove(path);collectgarbage('collect')
 if not valid then return nil,'查询数据格式无效或单条数据超过轻量查询上限',502 end
 -- A live connection list can shrink between pages; show an empty page, never fake a snapshot.
 return {rows=rows,total=total,page=page,checked=os.time()}
end
function I.query(view,page,q)
 if not M.lock('inspect.lock',30)then return nil,'查询正在进行，请稍后重试',503 end
 local ok,data,err,status=pcall(query,view,page,q)
 os.remove(M.R..'/inspect-'..require('nixio').getpid()..'.json')
 M.run('rmdir '..M.quote(M.R..'/inspect.lock')..' 2>/dev/null');os.remove(M.R..'/inspect.lock.time')
 if not ok then return nil,'查询未完成，请稍后重试',502 end
 return data,err,status
end
return I
