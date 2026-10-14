local original=dofile;local directory='/tmp/sc-assets-fixture'
os.execute('mkdir -p '..directory..'/assets; head -c 1200000 /dev/zero > '..directory..'/assets/large.js; gzip -c '..directory..'/assets/large.js > '..directory..'/assets/large.js.gz; rm '..directory..'/assets/large.js')
local M=original('/data/ShellCrash/ax5/common.lua');local quote=M.quote
M.quote=function(s)return quote(s:gsub('/tmp/ShellCrash%-dashboard',directory))end
local opened=io.open
io.open=function(path,mode)return opened(path:gsub('/tmp/ShellCrash%-dashboard',directory),mode)end
local headers,n,chunkmax,accepted,status={},0,0,'gzip',200
local H={header=function(k,v)headers[k]=v end,prepare_content=function(v)headers.type=v end,getenv=function()return accepted end,status=function(v)status=v end,write=function(v)n=n+#v;chunkmax=math.max(chunkmax,#v)end}
local D={context={request={'advancedasset','assets','large.js'}}}
package.loaded['luci.http']=H;package.loaded['luci.dispatcher']=D
_G.dofile=function(p)if p:match('/common.lua$')then return M end;return original(p)end
local A=original(arg[1]or'/data/ShellCrash/ax5/api.lua')
A.advancedasset();assert(headers['Content-Encoding']=='gzip'and headers.type=='application/javascript'and n<10000 and chunkmax<=4096)
headers={};n=0;chunkmax=0;accepted='';A.advancedasset();assert(not headers['Content-Encoding']and n==1200000 and chunkmax<=4096)
D.context.request={'advancedasset','..','secret.js'};A.advancedasset();assert(status==404)
io.open=opened;os.execute('rm -rf '..directory)
print('advanced assets: gzip negotiation, streamed >1 MB fallback, bounded chunks and traversal refusal passed')
