-- Exercise the real GUI/input fallback functions extracted from the module.
local source=assert(io.open("modules/checkers.lua","rb")):read("*a")
local function section(first,last)
    local a=assert(source:find(first,1,true),first)
    local b=assert(source:find(last,a,true),last)
    return source:sub(a,b-1)
end
local votes=section("local function safeSignalVote(b)","local function uniqueSorted")
local clicks, connections = {},0
local b={Name="AmericanButton",Visible=true,Active=true,AbsolutePosition={X=100,Y=100},AbsoluteSize={X=200,Y=100},MouseButton1Click={},Activated={}}
function b:IsA(c) return c=="GuiButton" end
function b:IsDescendantOf(a) return self==a end
local panel={};function panel:FindFirstChild(n) if n=="AmericanButton" then return b end end
local screen={Enabled=true};function screen:FindFirstChild(n) if n=="Panel" then return panel end end
local gui={Enabled=true}
local overlays={b}
local frames,waitHook=0,nil
local runService={RenderStepped={Wait=function()
    frames=frames+1
    if waitHook then waitHook() end
end}}
local pg={}
function pg:FindFirstChild(n) if n=="ModeSelectGui" then return screen end end
function pg:GetGuiObjectsAtPosition() return overlays end
local vim={};function vim:SendMouseButtonEvent(x,y,button,down)
    assert(gui.Enabled==false,"hub must be hidden during pointer injection")
    clicks[#clicks+1]={x=x,y=y,down=down}
end
local services={VirtualInputManager=vim}
local adapter={}
local env=setmetatable({adapter=adapter,playerGui=pg,gui=gui,controller={running=true},
    Workspace={CurrentCamera={ViewportSize={X=800,Y=600}}},UserInputService={},RunService=runService,
    game={GetService=function(_,name) return assert(services[name]) end},log=function() end,
    getconnections=function() return {{Enabled=true,Fire=function() connections=connections+1 end}} end,
}, {__index=_G})
local build=assert(load(votes.."\nreturn pointerClick", "input", "t", env))
local pointer=build()
local oldSize=b.AbsoluteSize;b.AbsoluteSize={X=0,Y=0}
assert(adapter.vote("American",1)==nil and #clicks==0 and connections==0,"unlaid button must wait without input")
b.AbsoluteSize=oldSize
assert(adapter.vote("American",1),"visible vote button should get virtual click")
assert(#clicks==2 and clicks[1].down and not clicks[2].down and clicks[1].x==200 and clicks[1].y==150)
assert(gui.Enabled==true and connections==0,"UI state restored; no duplicate connection invocation")
assert(frames==2,"wait for GUI update before input and keep mouse down for a frame")
-- A frame-delayed hit test sees the underlying vote button after the hub hides.
local window={Visible=true,Active=true};function window:IsDescendantOf() return false end
local beforeFrames=frames
function pg:GetGuiObjectsAtPosition() return frames>beforeFrames and not gui.Enabled and {b} or {window,b} end
assert(adapter.vote("American",1),"open hub must not intercept the delayed vote click")
assert(gui.Enabled and #clicks==4,"hub restored after delayed vote")
function pg:GetGuiObjectsAtPosition() return overlays end
-- If acknowledgement or Stop occurs while waiting, do not click or fallback.
local pending=true
waitHook=function() pending=false end
assert(not adapter.vote("American",1,function() return pending end),"ack during hide cancels vote")
waitHook=nil;assert(gui.Enabled and #clicks==4,"cancel restores GUI without clicking")
-- A button pressed before Stop is still released and the menu restored.
local beforeDown=frames
waitHook=function() if frames==beforeDown+2 then env.controller.running=false end end
assert(adapter.vote("American",1),"started virtual press is treated as an attempt")
waitHook=nil;assert(not env.controller.running and gui.Enabled and #clicks==6 and not clicks[6].down,"release and restore after Stop")
env.controller.running=true
-- A previously disabled hub must remain disabled; failures restore it too.
gui.Enabled=false
assert(adapter.vote("American",1) and not gui.Enabled,"closed hub remains disabled")
assert(#clicks==8);gui.Enabled=true
waitHook=function() error("frame wait failed") end
assert(not pointer(200,150,"vim",b) and gui.Enabled and #clicks==8,"error restores the hub")
waitHook=nil
-- Do not click through another active control.
local blocker={Visible=true,Active=true};function blocker:IsDescendantOf() return false end
overlays={blocker,b};env.getconnections=false
assert(not adapter.vote("American",1) and #clicks==8,"covered button is not clicked")
assert(gui.Enabled==true,"UI restored after blocked input")
-- No input after Stop.
overlays={b};env.controller.running=false
assert(not adapter.vote("American",1) and #clicks==8)
env.controller.running=true
-- If virtual input is unavailable, try the existing local connection route.
services.VirtualInputManager=nil;env.getconnections=function() return {{Enabled=true,Fire=function() connections=connections+1 end}} end
assert(adapter.vote("American",1) and connections==1)
assert(gui.Enabled==true)
-- Test physical retry guard: visible, raycast-confirmed piece only.
local retry=section("function adapter.retryPiece(id,stillPending)","function adapter.clickCell(row,col)")
local V={};V.__index=V
V.__sub=function(a,c) return setmetatable({X=a.X-c.X,Y=a.Y-c.Y,Z=a.Z-c.Z},V) end
V.__mul=function(a,n) return setmetatable({X=a.X*n,Y=a.Y*n,Z=a.Z*n},V) end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
local piece={Position=vec(0,0,10)};local wall={}
local camera={CFrame={Position=vec(0,0,0)}}
local onScreen=true
function camera:WorldToScreenPoint() return {X=200,Y=150,Z=10},onScreen end
local hit=wall;local count=0;local logs={}
local world={CurrentCamera=camera};function world:Raycast() return {Instance=hit} end
local retryAdapter={}
local retryEnv=setmetatable({adapter=retryAdapter,Workspace=world,player={Character={}},
    pieceFor=function() return piece end,log=function(kind,message) logs[#logs+1]=kind..":"..message end,
    safeDescendant=function() return false end,pointerClick=function() count=count+1;return true end,
    RaycastParams={new=function() return {} end},Enum={RaycastFilterType={Exclude=1}},
},{__index=_G})
assert(load(retry,"retry","t",retryEnv))()
assert(not retryAdapter.retryPiece("Piece2_1") and count==0,"occluded piece must not be clicked")
assert(logs[#logs]=="RETRY_GUARD:raycast_other_object")
hit=piece;assert(retryAdapter.retryPiece("Piece2_1") and count==1,"visible piece may get one retry")
onScreen=false;assert(not retryAdapter.retryPiece("Piece2_1") and count==1,"offscreen piece must not be clicked")
assert(logs[#logs]=="RETRY_GUARD:offscreen")
io.write("PASS: vote pointer fallback, UI blocking guards, restoration and piece raycast retry\n")
