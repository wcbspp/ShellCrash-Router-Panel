-- Run on the router: lua upload.lua /data/ShellCrash/ax5
local base=arg[1] or '/data/ShellCrash/ax5'
local original=dofile
local M=original(base..'/common.lua');M.R='/tmp/sc-upload-test'
os.execute('mkdir -p '..M.R)
local token=string.rep('t',24);M.write(M.R..'/csrf',token)
local payload,code,response
local H={getenv=function(k) return ({REQUEST_METHOD='POST',HTTP_X_SC_CSRF=token,CONTENT_LENGTH=tostring(#payload+20)})[k] end,
 formvalue=function()return payload end,status=function(c)code=c end,header=function()end,prepare_content=function()end,write=function(s)response=M.json.decode(s)end}
package.loaded['luci.http']=H;package.loaded['luci.dispatcher']={}
dofile=function(p)if p:match('/common.lua$')then return M end;return original(p)end
local A=original(base..'/api.lua')
local function send(d)payload=M.json.encode(d);code=nil;response=nil;A.upload();return code,response end
local input=string.rep('abcdefghij',5599)..'测试'
local encoded=require('nixio').bin.b64encode(input);local total=math.ceil(#encoded/2000)
M.write(M.R..'/upload-bounds','previous')
for i=0,total-1 do
 local c,r=send({id='1234abcd',kind='bounds',part=i,total=total,data=encoded:sub(i*2000+1,(i+1)*2000)})
 assert(c==200 and r.ok)
 if i<total-1 then assert(M.read(M.R..'/upload-bounds')=='previous' and not r.complete)end
end
assert(M.read(M.R..'/upload-bounds')==input)
assert(M.read(M.R..'/upload-id-bounds')=='1234abcd')
assert(send({id='1234abcd',kind='bounds',part=1,total=2,data='YQ=='})==409)
assert(send({id='1234abcd',kind='bounds',part=0,total=101,data='YQ=='})==400)
assert(send({id='1234abcd',kind='source',data='YQ=='})==200)
assert(M.read(M.R..'/upload-source')=='a')
os.execute('rm -rf '..M.R)
print('upload: large UTF-8, incomplete preservation, sequence, size limit, legacy passed')
