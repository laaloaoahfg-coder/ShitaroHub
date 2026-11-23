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
    Workspace={CurrentCamera={ViewportSize={X=800,Y=600}}},UserInputService={},
    game={GetService=function(_,name) return assert(services[name]) end},log=function() end,
    getconnections=function() return {{Enabled=true,Fire=function() connections=connections+1 end}} end,
}, {__index=_G})
local build=assert(load(votes.."\nreturn pointerClick", "input", "t", env))
local pointer=build()
assert(adapter.vote("American",1),"visible vote button should get virtual click")
assert(#clicks==2 and clicks[1].down and not clicks[2].down and clicks[1].x==200 and clicks[1].y==150)
assert(gui.Enabled==true and connections==0,"UI state restored; no duplicate connection invocation")
-- Do not click through another active control.
local blocker={Visible=true,Active=true};function blocker:IsDescendantOf() return false end
overlays={blocker,b};env.getconnections=false
assert(not adapter.vote("American",1) and #clicks==2,"covered button is not clicked")
assert(gui.Enabled==true,"UI restored after blocked input")
-- No input after Stop.
overlays={b};env.controller.running=false
assert(not adapter.vote("American",1) and #clicks==2)
env.controller.running=true
-- If virtual input is unavailable, try the existing local connection route.
services.VirtualInputManager=nil;env.getconnections=function() return {{Enabled=true,Fire=function() connections=connections+1 end}} end
assert(adapter.vote("American",1) and connections==1)
assert(gui.Enabled==true)
-- Test physical retry guard: visible, raycast-confirmed piece only.
local retry=section("function adapter.retryPiece(id)","function adapter.clickCell(row,col)")
local V={};V.__index=V
V.__sub=function(a,c) return setmetatable({X=a.X-c.X,Y=a.Y-c.Y,Z=a.Z-c.Z},V) end
V.__mul=function(a,n) return setmetatable({X=a.X*n,Y=a.Y*n,Z=a.Z*n},V) end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
local piece={Position=vec(0,0,10)};local wall={}
local camera={CFrame={Position=vec(0,0,0)}}
local onScreen=true
function camera:WorldToScreenPoint() return {X=200,Y=150,Z=10},onScreen end
local hit=wall;local count=0
local world={CurrentCamera=camera};function world:Raycast() return {Instance=hit} end
local retryAdapter={}
local retryEnv=setmetatable({adapter=retryAdapter,Workspace=world,player={Character={}},
    pieceFor=function() return piece end,log=function() end,
    safeDescendant=function() return false end,pointerClick=function() count=count+1;return true end,
    RaycastParams={new=function() return {} end},Enum={RaycastFilterType={Exclude=1}},
},{__index=_G})
assert(load(retry,"retry","t",retryEnv))()
assert(not retryAdapter.retryPiece("Piece2_1") and count==0,"occluded piece must not be clicked")
hit=piece;assert(retryAdapter.retryPiece("Piece2_1") and count==1,"visible piece may get one retry")
onScreen=false;assert(not retryAdapter.retryPiece("Piece2_1") and count==1,"offscreen piece must not be clicked")
io.write("PASS: vote pointer fallback, UI blocking guards, restoration and piece raycast retry\n")
