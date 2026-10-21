-- A bounded GET for the configured IPv4 HTTP WebDAV object, using existing nixio.
-- HTTPS and hostname repositories continue through curl with certificate checks.
return function(n,url,auth,expected)
 local host,port,path=url:match('^http://([%d%.]+):(%d+)(/[^%s]*)$')
 if not host then host,path=url:match('^http://([%d%.]+)(/[^%s]*)$');port='80' end
 if not host then return nil end
 local parts=0
 for part in host:gmatch('[^.]+')do
  if not part:match('^%d+$') or tonumber(part)>255 then return nil end
  parts=parts+1
 end
 if parts~=4 or not host:match('^%d+%.%d+%.%d+%.%d+$') then return nil end
 port=tonumber(port);assert(port and port>=1 and port<=65535,'invalid HTTP port')
 assert(path:match('^/[A-Za-z0-9/._~%%+%-]+$'),'invalid object path')
 local file=assert(io.open(auth,'r'))
 local text=file:read(8193);file:close()
 assert(text and #text<=8192,'invalid authentication file')
 local encoded=assert(text:match('^user%s*=%s*"(.-)"%s*$'),'invalid authentication record')
 local credentials,i={},1
 while i<=#encoded do
  local c=encoded:sub(i,i)
  if c=='\\' then
   i=i+1;c=encoded:sub(i,i)
   assert(c=='\\' or c=='"','invalid credential escape')
  else assert(c~='"','invalid credential quote')end
  assert(#c==1 and not c:find('[%c]'),'invalid credential character')
  credentials[#credentials+1]=c;i=i+1
 end
 credentials=table.concat(credentials)
 assert(credentials:match('^[^:]+:'),'invalid HTTP credentials')
 local socket=assert(n.socket('inet','stream'))
 local ok,result=pcall(function()
  assert(socket:setopt('socket','sndtimeo',8))
  assert(socket:setopt('socket','rcvtimeo',8))
  assert(socket:setopt('socket','rcvbuf',16384))
  assert(socket:connect(host,port),'HTTP repository connection failed')
  local request='GET '..path..' HTTP/1.1\r\nHost: '..host..':'..port..
   '\r\nAuthorization: Basic '..n.bin.b64encode(credentials)..
   '\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n'
  local position=1
  while position<=#request do
   local written=assert(socket:write(request:sub(position)))
   assert(written>0,'short HTTP request');position=position+written
  end
  -- Byte reads keep the archive body in the socket, avoiding a second body buffer.
  local header,deadline='',os.time()+15
  while header:sub(-4)~='\r\n\r\n' do
   assert(#header<8192 and os.time()<=deadline,'HTTP headers exceed bound')
   local c=assert(socket:read(1),'HTTP headers unavailable')
   assert(#c==1,'truncated HTTP headers');header=header..c
  end
  assert(header:match('^HTTP/1%.[01] 200[ \r]'),'HTTP object request rejected')
  local length
  for line in header:gmatch('[^\r\n]+')do
   if not line:match('^HTTP/') then
    local key,value=line:match('^([%w%-]+):%s*(.-)%s*$')
    assert(key,'invalid HTTP header');key=key:lower()
    if key=='content-length' then
     assert(not length and value:match('^%d+$'),'invalid HTTP length')
     length=tonumber(value)
    elseif key=='transfer-encoding' then error('unsupported HTTP transfer encoding')
    elseif key=='content-encoding' then assert(value:lower()=='identity','encoded HTTP object')end
   end
  end
  assert(length==expected,'HTTP object length mismatch')
  assert(socket:setblocking(false))
  return socket
 end)
 if not ok then pcall(function()socket:close()end);error(result)end
 return result
end
