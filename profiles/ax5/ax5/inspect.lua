local M=(...)or dofile('/data/ShellCrash/ax5/common.lua')
local I={}
local function bytes(value)
 local v=tonumber(value);if not v or v<0 or v~=v or v==math.huge then return '待统计'end
 local units={'B','KB','MB','GB','TB'};local i=1
 while v>=1024 and i<#units do v=v/1024;i=i+1 end
 return i==1 and string.format('%d B',v)or string.format('%.1f %s',v,units[i])
end
-- Parse one JSON object at a time from the kernel's top-level array response.
-- Keeping the full rules response as Lua tables costs several MB on AX5.
function I.each_object(path,key,visit,map,root_only)
 local f=type(path)=='string'and io.open(path,'rb')or path;if not f then return false end
 local consumed=0
 local prefix,started,finished='',false,false
 local seek_depth,seek_string,seek_escape=0,false,false
 local depth,in_string,escaped=0,false,false
 local pieces,size,n={},0,0
 local key_phase,key_parts,key_escaped,member_key='key',{},false,nil
 local function abort()f:close();return false end
 while true do
  local block=f:read(4096);if not block then break end
  local segment_start=depth>0 and 1 or nil
  consumed=consumed+#block;if consumed>4194304 then f:close();return false,'limit'end
  for pos=1,#block do
   local ch=block:sub(pos,pos)
   if not started then
    prefix=prefix..ch
    local matches=prefix:match('"'..key..'"%s*:%s*'..(map and '%{'or'%[')..'$')
    if matches and(not root_only or(seek_depth==1 and not seek_string))then started=true;prefix=''
    elseif root_only then
     if seek_string then
      if seek_escape then seek_escape=false elseif ch=='\\'then seek_escape=true elseif ch=='"'then seek_string=false end
     elseif ch=='"'then seek_string=true
     elseif ch=='{'or ch=='['then seek_depth=seek_depth+1
     elseif ch=='}'or ch==']'then seek_depth=seek_depth-1 end
     if #prefix>128 then prefix=prefix:sub(-128)end
    elseif #prefix>8192 then return abort()end
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
    elseif ch=='{'then depth=1;pieces={};size=0;segment_start=pos;in_string=false;escaped=false
    elseif not ch:match('[%s,]')then return abort()end
   else
    if size+pos-segment_start+1>16384 then return abort()end
    if in_string then
     if escaped then escaped=false elseif ch=='\\'then escaped=true elseif ch=='"'then in_string=false end
    elseif ch=='"'then in_string=true
    elseif ch=='{'then depth=depth+1
    elseif ch=='}'then
     depth=depth-1
     if depth==0 then
      pieces[#pieces+1]=block:sub(segment_start,pos);segment_start=nil
      local ok,obj=pcall(M.json.decode,table.concat(pieces));pieces={};if not ok then return abort()end
      n=n+1;visit(obj,n,member_key);key_phase='key';if n%50==0 then collectgarbage('collect')end
     end
    end
   end
  end
  if segment_start then local part=block:sub(segment_start);pieces[#pieces+1]=part;size=size+#part end
  if finished then break end
 end
 f:close();collectgarbage('collect');return started and finished and depth==0
end

local function query(view,page,q)
 local paths={rules='/rules',groups='/proxies',connections='/connections'}
 if not paths[view] or #q>128 or not page or page<0 or page>10000 or page~=math.floor(page)then return nil,'查询参数无效',400 end
 if M.load(M.R..'/job.json').active then return nil,'正在处理配置，请稍后查询',503 end
 if M.pid()==0 then return nil,'代理已停止，启动后可查询运行数据',503 end
 -- Stream one object at a time: no response file in tmpfs. The additional
 -- 256 KB covers the bounded object parser, group descriptors and output page.
 collectgarbage('collect')
 local mem=M.memory();local available=mem.MemAvailable or mem.MemFree or 0;local reserve=M.limits().protect_mb*1024+256
 if available<reserve then return nil,string.format('内存余量不足，暂缓查询（当前 %.1f MB；查询至少需要 %.1f MB）',available/1024,reserve/1024),503 end
 local stream,code=dofile(M.C..'/ax5/core-stream.lua').open(paths[view])
 if not stream then return nil,'内核查询失败，请稍后重试',code or 502 end
 local rows={};local total=0;local first=page*20;local query=q:lower()
 local function add(title,detail,order)
  title=tostring(title or'—');detail=tostring(detail or'')
  if not (title..' '..detail):lower():find(query,1,true)then return end
  total=total+1;if total>first and total<=first+20 then
   local function clip(text,n)if #text<=n then return text end;return text:sub(1,n):gsub('[\194-\244][\128-\191]*$','')..'…'end
   rows[#rows+1]={title=clip(title,256),detail=clip(detail,768),order=order}
  end
 end
 local valid,parse_error=true,nil
 if view=='rules'then
  valid,parse_error=I.each_object(stream,'rules',function(r,n)add(r.payload or r.rule or r.ruleSet or r.type,(r.type or'')..' → '..(r.proxy or r.outbound or''),n)end)
 elseif view=='groups'then
  local groups={};local groups_limited=false
  valid,parse_error=I.each_object(stream,'proxies',function(p,_,name)
   if type(p.all)=='table'then
    if #groups>=128 or #name>256 or #tostring(p.now or'')>256 then groups_limited=true;return end
    groups[#groups+1]={name=name,kind=p.type,count=#p.all,now=p.now}
   end
  end,true)
  if groups_limited then return nil,'策略组超过轻量查询上限，请在高级面板查看',413 end
  table.sort(groups,function(a,b)return a.name<b.name end)
  for _,p in ipairs(groups)do add(p.name,(p.kind or'策略组')..' · '..p.count..' 个成员 · 当前 '..(p.now or'未选择'))end
 else
  valid,parse_error=I.each_object(stream,'connections',function(c)
   local m=c.metadata or{};local target=m.destinationIP and(m.destinationIP..':'..tostring(m.destinationPort or''))or''
   local bits={m.network or'',m.sourceIP and(m.sourceIP..':'..tostring(m.sourcePort or'')..' → '..target)or target,'↑ '..bytes(c.upload)..' / ↓ '..bytes(c.download),table.concat(c.chains or{},' → '),c.rule and(c.rule..(c.rulePayload and(' / '..c.rulePayload)or''))or''};add(m.host or m.destinationIP or'未知目标',table.concat(bits,' · '))
  end)
 end
 collectgarbage('collect')
 if parse_error=='limit'then return nil,'数据超过轻量查询的 4 MB 上限，请在高级面板查看',413 end
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
