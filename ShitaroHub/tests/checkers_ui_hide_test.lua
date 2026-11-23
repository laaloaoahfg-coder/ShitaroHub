-- Check the actual hide callback uses the existing toggle/cursor cleanup path.
local f=assert(io.open("core/ui.lua","rb"));local source=f:read("*a");f:close()
local start=assert(source:find("uiState.hideMenu = function()",1,true))
local finish=assert(source:find("\nend",start,true))+3
local window={Visible=true};local uiState={closed=false};local toggles=0
local env=setmetatable({window=window,uiState=uiState,toggleMenu=function()
    toggles=toggles+1;window.Visible=not window.Visible
end},{__index=_G})
assert(load(source:sub(start,finish),"hideMenu","t",env))()
uiState.hideMenu();assert(not window.Visible and toggles==1)
uiState.hideMenu();assert(not window.Visible and toggles==1,"already hidden must not reopen")
window.Visible=true;uiState.closed=true;uiState.hideMenu()
assert(window.Visible and toggles==1,"shutdown does not toggle menu")
assert(source:find("hideMenu = function() if uiState.hideMenu then uiState.hideMenu() end end",1,true),"context delegates to callback")
io.write("PASS: menu hide reuses toggle and does not reopen closed or shut down UI\n")
