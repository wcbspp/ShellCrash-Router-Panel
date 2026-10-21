-- Bounded archive fan-out using existing firmware nixio pipes, not named FIFOs.
-- Hash compressed bytes while gzip feeds a bounded parser; execute nothing here.
local n=require('nixio')
assert(n.signal(13,'ign')) -- A rejected parser must return EPIPE, not kill cleanup.
assert(n.umask(63))
local url,size,blob,sha,output,receipt,ca,parser=unpack(arg)
local auth=arg[9] or ''
size=assert(tonumber(size));assert(size>0 and size<=10485760,'invalid archive size')
assert(blob:match('^[a-f0-9]+$') and #blob==40,'missing pinned blob')
assert(sha=='' or (sha:match('^[a-f0-9]+$') and #sha==64),'invalid archive hash')
assert(url:match('^https?://') and not url:find('[%c]'),'invalid archive URL')
assert(auth=='' or (auth:match('^/[A-Za-z0-9/._%-]+$') and not auth:find('..',1,true)),'invalid authentication file')
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
local children,handles={},{}
local function close(fd)if fd then pcall(function()fd:close()end)end end
local function spawn(command,reader)
 local a,b=assert(n.pipe());local pid=assert(n.fork())
 if pid==0 then
  for _,fd in ipairs(handles)do close(fd)end
  if reader then close(a);assert(n.dup(b,n.stdout));close(b)
  else close(b);assert(n.dup(a,n.stdin));close(a)end
  n.exec('/bin/sh','-c',command);os.exit(127)
 end
 children[#children+1]=pid
 local fd=reader and a or b;close(reader and b or a);handles[#handles+1]=fd;return fd
end
local function write(fd,s)
 local pos=1
 while pos<=#s do local k=assert(fd:write(s:sub(pos)));assert(k>0,'short pipe write');pos=pos+k end
end
local function hash(path)
 local f=assert(io.open(path));local s=f:read('*a');f:close()
 return s:match('^([a-f0-9]+)%s') or s:match('([a-f0-9]+)%s*$')
end
local temporary={receipt..'.sha1',receipt..'.sha256',receipt..'.extract'}
local ok,err=pcall(function()
 local deadline=os.time()+240
 local download_transport
 local function open_download()
  local download
  if auth~='' and url:match('^http://') then
   local directory=assert(parser:match('^(.*/)[^/]+$'))
   download=assert(loadfile(directory..'core_http.lua'))()(n,url,auth,size)
   if download then handles[#handles+1]=download;download_transport='native-http' end
  end
  if not download then
   local credentials=auth~='' and (' --config '..quote(auth)) or ''
   download=spawn('exec curl -4'..credentials..' --noproxy '..quote('*')..' --cacert '..quote(ca)..' -fsSL --connect-timeout 8 --max-time 120 --max-filesize '..size..' '..quote(url),true)
   download_transport='curl'
  end
  assert(download:setblocking(false));return download
 end
 local function wait_children()
  while #children>0 do
   local pid=children[1];local p,why,code=n.waitpid(pid)
   -- A reaped PID can be reused; never include it in later error cleanup.
   if p==pid then table.remove(children,1)end
   assert(p==pid and why=='exited' and code==0,'archive pipeline failed')
  end
 end
 -- First authenticate a bounded compressed stream without allocating any
 -- candidate. Bind its SHA256 to the source's pinned Git blob, then reap the
 -- OpenSSL process before the physical extraction-reserve check in pass two.
 local h1=spawn('exec openssl dgst -sha1 > '..quote(temporary[1]),false)
 local h2=spawn('exec sha256sum > '..quote(temporary[2]),false)
 write(h1,'blob '..size..'\0')
 local source=open_download()
 local first_size=0
 while true do
  assert(os.time()<=deadline,'archive pipeline timed out')
  local s,code,message=source:read(4096)
  if s==false and code==11 then
   local ready,reason,detail=n.poll({{fd=source,events=n.poll_flags('in')}},1000)
   assert(ready or reason==4,detail or 'archive input poll failed')
  else
   assert(s,message or 'archive input failed')
   if #s==0 then break end
   first_size=first_size+#s;assert(first_size<=size,'archive body exceeds bound')
   write(h1,s);write(h2,s)
  end
 end
 close(source);close(h1);close(h2);wait_children()
 assert(first_size==size,'archive length mismatch')
 local verified_sha=assert(hash(temporary[2]))
 assert(hash(temporary[1])==blob,'archive blob mismatch')
 assert(sha=='' or verified_sha==sha,'archive sha256 mismatch')
 for _,fd in ipairs(handles)do close(fd)end
 handles={};h1=nil;h2=nil;source=nil
 collectgarbage('collect')
 -- Pass two has no OpenSSL process. Its SHA256 must match the fully verified
 -- first pass, so changing the object between requests cannot authorize bytes.
 -- Every remaining helper exists BEFORE the unchanged 24MiB reserve check.
 h2=spawn('exec sha256sum > '..quote(temporary[2]),false)
 -- Decode through two anonymous pipes, but parse in THIS Lua process. A second
 -- Lua plus pipeline shells cost too much on the 128MiB target. Nonblocking
 -- gzip I/O prevents a full output pipe from deadlocking its compressed input.
 local input,feed=assert(n.pipe());local decoded,sink=assert(n.pipe())
 local gzip=assert(n.fork())
 if gzip==0 then
  for _,fd in ipairs(handles)do close(fd)end
  close(feed);close(decoded)
  assert(n.dup(input,n.stdin));assert(n.dup(sink,n.stdout))
  close(input);close(sink);n.exec('/bin/gzip','-dc');os.exit(127)
 end
 children[#children+1]=gzip;close(input);close(sink)
 handles[#handles+1]=feed;handles[#handles+1]=decoded
 assert(feed:setblocking(false));assert(decoded:setblocking(false))
 local download=open_download()
 collectgarbage('collect')
 local received,pending,ended,gzip_end=0,'',false,false
 local function read(fd,count)
  local s,code,message=fd:read(count)
  if s==false and code==11 then return nil end -- firmware EAGAIN
  assert(s,message or 'pipe read failed');return s
 end
 local function next_bytes(count)
  local buffer=''
  while #buffer<count and not gzip_end do
   assert(os.time()<=deadline,'archive pipeline timed out')
   local progress=false
   local s=read(decoded,math.min(65536,count-#buffer))
   if s then
    if #s==0 then gzip_end=true else buffer=buffer..s end
    progress=true
   end
   if #buffer<count and not gzip_end then
    if #pending>0 then
     local written,code,message=feed:write(pending)
     if written then
      assert(written>0,'short gzip pipe write');pending=pending:sub(written+1);progress=true
     else assert(code==11,message or 'gzip pipe write failed')end
    end
    if #pending==0 and not ended then
     s=read(download,4096)
     if s then
      if #s==0 then
       ended=true;close(download);close(h2)
      else
       received=received+#s;assert(received<=size,'archive body exceeds bound')
       write(h2,s);pending=s
      end
      progress=true
     end
    end
    if ended and #pending==0 and feed then close(feed);feed=nil;progress=true end
    if not progress then
     local fds={{fd=decoded,events=n.poll_flags('in')}}
     if #pending>0 then fds[#fds+1]={fd=feed,events=n.poll_flags('out')}
     elseif not ended then fds[#fds+1]={fd=download,events=n.poll_flags('in')}end
     local ready,code,message=n.poll(fds,1000)
     assert(ready or code==4,message or 'archive pipe poll failed') -- retry EINTR
    end
   end
  end
  return #buffer>0 and buffer or nil
 end
 local original_stdin,original_arg=io.stdin,arg
 io.stdin={read=function(_,count)return next_bytes(count)end}
 arg={output,temporary[3]}
 local parsed,parse_error=pcall(function()assert(loadfile(parser))()end)
 io.stdin,arg=original_stdin,original_arg
 if not parsed then io.stderr:write('core_stream_transport=',download_transport,' verification_passes=2\n')end
 assert(parsed,parse_error)
 assert(ended and #pending==0,'archive input incomplete')
 close(decoded)
 wait_children()
 assert(received==size,'archive length mismatch')
 local digest=assert(hash(temporary[2]))
 assert(digest==verified_sha,'archive changed between verification passes')
 local metadata=assert(io.open(temporary[3])):read('*a')
 local f=assert(io.open(receipt,'w'));assert(f:write('sha256=',digest,'\ndownload_transport=',download_transport,'\nverification_passes=2\n',metadata));assert(f:close())
end)
for _,fd in ipairs(handles)do close(fd)end
if not ok then
 for _,pid in ipairs(children)do pcall(n.kill,pid,15)end
 for _,pid in ipairs(children)do pcall(n.waitpid,pid)end
 os.remove(output);os.remove(receipt)
end
for _,path in ipairs(temporary)do os.remove(path)end
if not ok then io.stderr:write(tostring(err),'\n');os.exit(1)end
