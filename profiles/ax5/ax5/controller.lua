module("luci.controller.web.shellcrash", package.seeall)
function index()
 entry({"web","shellcrash"},call("page"),"ShellCrash",90)
 for _,name in ipairs({"panel","asset","read","control","upload","api","advancedasset"}) do
  entry({"web","shellcrash",name},call(name)).leaf=true
 end
end
local function app() return dofile("/data/ShellCrash/ax5/api.lua") end
function page() luci.template.render("web/shellcrash") end
function panel() app().panel() end
function asset() app().asset() end
function read() app().read() end
function control() app().control() end
function upload() app().upload() end
function api() app().api() end

function advancedasset() app().advancedasset() end
