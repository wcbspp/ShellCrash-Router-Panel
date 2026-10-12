-- Run with Lua/cjson: lua tests/selection.lua ax5/state.lua
local path=arg[1] or '/data/ShellCrash/ax5/state.lua'
local json=require('cjson');local saved,calls={}, {}
local live={proxies={manual={type='Selector',now='node1'},automatic={type='URLTest',now='node2'},GLOBAL={type='Selector',now='manual'}}}
local M={C='/fixture',R='/runtime',json=json,pid=function()return 1 end}
function M.load(p) if p:match('selectors.json$') then return saved end;return {events={}} end
function M.save(p,v) if p:match('selectors.json$')then saved=v end end
function M.read()return '' end
function M.write()end
function M.api(path,method,body) if method then calls[#calls+1]={path,method};return '' end;return json.encode(live) end
local original=dofile;dofile=function(p)if p:match('common.lua$')then return M end;return original(p)end
saved={manual='old',automatic='old-auto',removed='old'};arg={'save-selection'};assert(loadfile(path))()
assert(saved.manual=='node1' and saved.automatic==nil and saved.removed==nil)
saved={manual='node1',automatic='node2',removed='old'};arg={'restore'};assert(loadfile(path))()
assert(#calls==1 and calls[1][1]=='/proxies/manual')
print('Manual selection persistence and automatic-group restore isolation passed')
