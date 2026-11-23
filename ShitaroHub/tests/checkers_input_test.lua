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
-- A moving vote button is a transient layout wait, not a failed attempt.
local oldX=b.AbsolutePosition.X
waitHook=function() b.AbsolutePosition.X=oldX+10 end
assert(adapter.vote("American",1)==nil,"moving button must retry after layout settles")
waitHook=nil;b.AbsolutePosition.X=oldX;assert(gui.Enabled and #clicks==4,"layout wait must not click")
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
-- Mouse retry moves, waits a frame, clicks, waits, and restores the cursor.
local mouseMoves,mouseClicks={},0
env.mousemoveabs=function(x,y) mouseMoves[#mouseMoves+1]={x,y} end
env.mouse1click=function() mouseClicks=mouseClicks+1 end
function env.UserInputService:GetMouseLocation() return {X=25,Y=30} end
local frameBeforeMouse=frames
assert(pointer(200,150,"mouse",b) and frames==frameBeforeMouse+3 and mouseClicks==1)
assert(#mouseMoves==2 and mouseMoves[2][1]==25 and mouseMoves[2][2]==30 and gui.Enabled)
-- A pending action cancelled after moving restores the mouse but never clicks.
local still=true;local frameBeforeCancel=frames
waitHook=function() if frames==frameBeforeCancel+2 then still=false end end
assert(not pointer(200,150,"mouse",b,function() return still end))
waitHook=nil;assert(mouseClicks==1 and #mouseMoves==4 and mouseMoves[4][1]==25 and gui.Enabled)
-- For 3D input, compare the engine's actual Mouse.Target after moving.
local actualTarget,plannedPart={},{}
env.player={GetMouse=function() return {Target=actualTarget} end}
services.VirtualInputManager=vim;overlays={}
local moves={}
function vim:SendMouseMoveEvent(x,y) moves[#moves+1]={x,y} end
local beforeVirtual=#clicks
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"wrong engine target must not receive virtual click")
assert(#clicks==beforeVirtual and #moves==2 and moves[2][1]==25 and gui.Enabled,"wrong target restores cursor and hub")
actualTarget=nil
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"nil engine target must not receive click")
assert(#clicks==beforeVirtual)
actualTarget=plannedPart
assert(pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"matching target may receive virtual click")
assert(#clicks==beforeVirtual+2 and clicks[#clicks-1].down and not clicks[#clicks].down,"virtual pointer press and release")
local beforeMouseClicks=mouseClicks
actualTarget={}
assert(not pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(mouseClicks==beforeMouseClicks and gui.Enabled,"wrong mouse target never clicked")
-- Stop before the actual press cancels virtual input, restores the cursor.
actualTarget=plannedPart;local beforeCancelClicks=#clicks;local cancelFrame=frames
waitHook=function() if frames==cancelFrame+2 then env.controller.running=false end end
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart))
waitHook=nil;env.controller.running=true;assert(#clicks==beforeCancelClicks and gui.Enabled)
-- If Stop arrives after the virtual button-down, the button is still released.
actualTarget=plannedPart;local beforeHeld=#clicks;local heldFrame=frames
waitHook=function() if frames==heldFrame+3 then env.controller.running=false end end
assert(pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart))
waitHook=nil;assert(#clicks==beforeHeld+2 and clicks[#clicks-1].down and not clicks[#clicks].down and gui.Enabled,"virtual button releases after Stop")
env.controller.running=true
-- Exercise the real alternate-detector selection logic separately.
local alternate=section("function adapter.retryDetector(id)","function adapter.retryPiece(id,stillPending,method)")
local hitDet,rootDet={},{}
local hitbox={FindFirstChildOfClass=function() return hitDet end}
local detPart={FindFirstChild=function() return hitbox end,FindFirstChildOfClass=function() return rootDet end}
local altCount=0;local altAdapter={}
local altEnv=setmetatable({adapter=altAdapter,pieceFor=function() return detPart end,log=function() end,
    clickDetector=function(d) assert(d==rootDet);altCount=altCount+1;return true end},{__index=_G})
assert(load(alternate,"alternate","t",altEnv))()
assert(altAdapter.retryDetector("Piece1_1") and altCount==1,"alternate uses the distinct root detector")
rootDet=hitDet;assert(altAdapter.retryDetector("Piece1_1")==nil and altCount==1,"same detector must not be retried")
-- The visual guide attaches only to the planned piece and is cleaned up.
local guideSource=section("local guideHighlight", "function adapter.selectPiece(id)")
local guideObjects={}
local guideAdapter={}
local guidePiece={}
local guideEnv=setmetatable({adapter=guideAdapter,pieceFor=function() return guidePiece end,
    Instance={new=function(kind)
        assert(kind=="Highlight");local mark={}
        function mark:Destroy() self.destroyed=true end
        guideObjects[#guideObjects+1]=mark;return mark
    end},Color3={fromRGB=function(...) return {...} end},
    Enum={HighlightDepthMode={AlwaysOnTop=1}},log=function() end},{__index=_G})
assert(load(guideSource,"guide","t",guideEnv))()
assert(guideAdapter.showGuide("Piece1_2") and guideObjects[1].Parent==guidePiece and guideObjects[1].Adornee==guidePiece)
guideAdapter.clearGuide();assert(guideObjects[1].destroyed,"guide must be destroyed")
guideEnv.pieceFor=function() return nil end;assert(not guideAdapter.showGuide("missing"),"do not mark missing piece")
local guideCell={Name="Move",Parent={}}
guideEnv.cells={[5]={[4]=guideCell}};guideAdapter.isSeated=function() return true end
assert(guideAdapter.showCellGuide(5,4) and guideObjects[2].Adornee==guideCell,"highlight exact confirmed cell")
guideAdapter.clearGuide();assert(guideObjects[2].destroyed)
guideCell.Name="BlockMove";assert(not guideAdapter.showCellGuide(5,4),"inactive cell cannot be highlighted")
guideCell.Name="Move";guideAdapter.isSeated=function() return false end
assert(not guideAdapter.showCellGuide(5,4),"do not highlight after leaving the table")
-- Test physical retry guard: visible, raycast-confirmed piece only.
local retry=section("local function retryVisible(","function adapter.clickCell(row,col)")
local V={};V.__index=V
V.__sub=function(a,c) return setmetatable({X=a.X-c.X,Y=a.Y-c.Y,Z=a.Z-c.Z},V) end
V.__mul=function(a,n) return setmetatable({X=a.X*n,Y=a.Y*n,Z=a.Z*n},V) end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
local piece={Position=vec(0,0,10)};local wall={}
local camera={CFrame={Position=vec(0,0,0)}}
local onScreen=true
function camera:WorldToViewportPoint() return {X=200,Y=150,Z=10},onScreen end
function camera:WorldToScreenPoint() return {X=200,Y=114,Z=10},onScreen end
local hit=wall;local count=0;local logs={}
local world={CurrentCamera=camera};function world:Raycast() return {Instance=hit} end
local retryAdapter={}
local selectedMethod,lastGuiPoint,lastX,lastY
local retryEnv=setmetatable({adapter=retryAdapter,Workspace=world,player={Character={}},UserInputService={TouchEnabled=true},
    pieceFor=function() return piece end,log=function(kind,message) logs[#logs+1]=kind..":"..message end,
    safeDescendant=function() return false end,pointerClick=function(x,y,method,expected,valid,guiPoint)
        assert(valid(),"target must still be valid");count=count+1;selectedMethod=method;lastGuiPoint=guiPoint;lastX=x;lastY=y;return true
    end,
    RaycastParams={new=function() return {} end},Enum={RaycastFilterType={Exclude=1}},
},{__index=_G})
assert(load(retry,"retry","t",retryEnv))()
assert(not retryAdapter.retryPiece("Piece2_1") and count==0,"occluded piece must not be clicked")
assert(logs[#logs]=="RETRY_GUARD:raycast_other_object")
hit=piece;assert(retryAdapter.retryPiece("Piece2_1") and count==1,"visible piece may get one retry")
assert(selectedMethod=="touch" and lastX==200 and lastY==150 and lastGuiPoint.Y==114,"viewport input differs from inset-relative GUI hit test")
assert(retryAdapter.retryPiece("Piece2_1",function() return true end,"virtual") and selectedMethod=="vim3d","explicit virtual retry uses the virtual pointer path")
count=count-1
-- If touch could not even start, fall back to the mouse; no second method is
-- attempted after a touch start reported success.
local methodOrder={}
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint)
    methodOrder[#methodOrder+1]=method;assert(valid())
    return method~="touch"
end
assert(retryAdapter.retryPiece("Piece2_1") and #methodOrder==2 and methodOrder[1]=="touch" and methodOrder[2]=="mouse")
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint)
    assert(valid());count=count+1;selectedMethod=method;lastGuiPoint=guiPoint;lastX=x;lastY=y;return true
end
-- When centre is blocked, a different sample is used only if its own ray
-- actually reaches the intended piece. The obstacle is never ignored.
local box={Transparency=1,CanQuery=true,CanCollide=false}
retryEnv.model={FindFirstChild=function(_,name)
    if name=="Functional" then return {FindFirstChild=function(_,n) if n=="Box" then return box end end} end
end}
piece.Size={X=2,Y=1,Z=2}
piece.CFrame={PointToWorldSpace=function(_,offset) return vec(offset.X,offset.Y,10+offset.Z) end}
retryEnv.Vector3={new=vec}
local oldRay=world.Raycast
function world:Raycast(origin,direction)
    if direction.X>0.1 then return {Instance=piece} end
    return {Instance=box}
end
local afterCentre=count
assert(retryAdapter.retryPiece("Piece2_1") and count==afterCentre+1,"safe side sample reaches the piece")
local joined=table.concat(logs,"\n")
assert(joined:find("RETRY_HIT:functional_box",1,true) and joined:find("RETRY_SAMPLE:index=3",1,true) and joined:find("canQuery=true canCollide=false",1,true),"obstacle and chosen sample logged")
world.Raycast=oldRay;piece.Size=nil;piece.CFrame=nil;retryEnv.Vector3=nil;retryEnv.model=nil;count=count-1
onScreen=false;assert(not retryAdapter.retryPiece("Piece2_1") and count==1,"offscreen piece must not be clicked")
assert(logs[#logs]=="RETRY_GUARD:offscreen")
-- Only the server-confirmed, still active destination can be physically retried.
onScreen=true
local cell={Position=vec(0,0,10),Parent={},Name="Move"};hit=cell
retryEnv.cells={[5]={[4]=cell}};retryAdapter.isSeated=function() return true end
assert(retryAdapter.retryCell(5,4,function() return true end) and count==2,"confirmed cell retry")
cell.Name="BlockMove";assert(not retryAdapter.retryCell(5,4,function() return true end) and count==2,"inactive cell cannot be retried")
cell.Name="Move";hit=wall;assert(not retryAdapter.retryCell(5,4,function() return true end) and count==2,"occluded cell cannot be clicked")
-- Touch starts and ends even if Stop happens in the middle; GUI testing uses inset coordinates.
services.VirtualInputManager=vim;overlays={}
local touchCalls={};local checkedX,checkedY
function pg:GetGuiObjectsAtPosition(x,y) checkedX,checkedY=x,y;return overlays end
function vim:SendTouchEvent(id,state,x,y) touchCalls[#touchCalls+1]={id,state,x,y} end
local beforeTouch=frames
waitHook=function() if frames==beforeTouch+2 then env.controller.running=false end end
assert(pointer(200,150,"touch",nil,function() return true end,{X=200,Y=114}),"touch should start")
waitHook=nil;assert(#touchCalls==2 and touchCalls[1][2]==0 and touchCalls[2][2]==2 and checkedX==200 and checkedY==114 and gui.Enabled,"touch release and inset GUI guard")
env.controller.running=true
io.write("PASS: vote pointer fallback, UI blocking guards, restoration and piece raycast retry\n")
