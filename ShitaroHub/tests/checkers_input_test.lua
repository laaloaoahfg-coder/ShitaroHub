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
local shouldHide=true
local vim={};function vim:SendMouseButtonEvent(x,y,button,down)
    assert(gui.Enabled~=shouldHide,"hub hidden only for vote input, visible for world input")
    clicks[#clicks+1]={x=x,y=y,down=down}
end
local services={VirtualInputManager=vim}
local adapter={}
local env=setmetatable({adapter=adapter,playerGui=pg,gui=gui,controller={running=true},
    Workspace={CurrentCamera={ViewportSize={X=800,Y=600}}},UserInputService={},RunService=runService,
    game={GetService=function(_,name) return assert(services[name]) end},log=function() end,
    getconnections=function() return {{Enabled=true,Fire=function() connections=connections+1 end}} end,
}, {__index=_G})
local build=assert(load(votes.."\nreturn pointerClick,function() cursor3dUnsafe={mouse=false,virtual=false} end", "input", "t", env))
local pointer,resetCursor=build()
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
local mousePosition={X=25,Y=30}
env.mousemoveabs=function(x,y) mouseMoves[#mouseMoves+1]={x,y};mousePosition={X=x,Y=y} end
env.mouse1click=function() mouseClicks=mouseClicks+1 end
function env.UserInputService:GetMouseLocation() return mousePosition end
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
shouldHide=false
env.player={GetMouse=function() return {Target=actualTarget} end}
services.VirtualInputManager=vim;overlays={}
local moves={}
function vim:SendMouseMoveEvent(x,y) moves[#moves+1]={x,y};mousePosition={X=x,Y=y} end
local beforeVirtual=#clicks
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"wrong engine target must not receive virtual click")
assert(#clicks==beforeVirtual and #moves==2 and moves[2][1]==25 and gui.Enabled,"wrong target restores cursor and hub")
actualTarget=nil
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"nil engine target must not receive click")
assert(#clicks==beforeVirtual)
actualTarget=plannedPart
waitHook=function() assert(gui.Enabled,"world retry must never hide the HUD during a frame") end
assert(pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart),"matching target may receive virtual click")
waitHook=nil
assert(#clicks==beforeVirtual+2 and clicks[#clicks-1].down and not clicks[#clicks].down,"virtual pointer press and release")
-- A visible active HUD control still blocks a 3D press instead of being hidden.
overlays={blocker};local beforeOverlay=#clicks
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(#clicks==beforeOverlay and gui.Enabled,"active HUD remains visible and protects its controls")
overlays={}
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
-- Prefer a held press/release where available; Stop after down must still
-- release, restore cursor and never fall back to an additional click.
local pressCount,releaseCount=0,0
env.mouse1press=function() pressCount=pressCount+1 end
env.mouse1release=function() releaseCount=releaseCount+1 end
actualTarget=plannedPart;local heldMouseFrame=frames
waitHook=function() if frames==heldMouseFrame+3 then env.controller.running=false end end
assert(pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart))
waitHook=nil;assert(pressCount==1 and releaseCount==1 and gui.Enabled and not env.controller.running)
env.controller.running=true;env.mouse1press=nil;env.mouse1release=nil
-- A bad executor coordinate mapping never presses or restores to an
-- unreliable position; an independent VIM path may still be verified.
local previousMove=env.mousemoveabs;local mismatchMoves=0
mousePosition={X=25,Y=30};actualTarget=plannedPart
local beforeMismatch=mouseClicks
local checkLog={};env.log=function(k,m) checkLog[#checkLog+1]=k..":"..m end
env.mousemoveabs=function() mismatchMoves=mismatchMoves+1;mousePosition={X=799,Y=599} end
assert(not pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(mismatchMoves==1 and mouseClicks==beforeMismatch and gui.Enabled,"mismatch skips click and unsafe restore")
assert(table.concat(checkLog,"\n"):find("cursor position mismatch",1,true))
local movesAfterMismatch=#moves
assert(pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(#moves==movesAfterMismatch+2 and gui.Enabled,"mouse mismatch does not disable independently verified virtual pointer")
assert(not pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart) and mismatchMoves==1,"bad mouse backend stays disabled")
resetCursor();env.mousemoveabs=previousMove;mousePosition={X=25,Y=30}
-- A mismatched virtual pointer likewise must not poison the mouse backend.
local oldVimMove=vim.SendMouseMoveEvent
function vim:SendMouseMoveEvent() mousePosition={X=799,Y=599} end
local oldVirtualClicks=#clicks
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(#clicks==oldVirtualClicks,"incorrect virtual coordinate must never click")
mousePosition={X=25,Y=30};vim.SendMouseMoveEvent=oldVimMove
assert(pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart),"independent mouse remains eligible")
resetCursor();mousePosition={X=25,Y=30};beforeMismatch=mouseClicks
-- Invalid cursor origin is not restored or clicked.
mousePosition={X=1e30,Y=1e30};local oldMoveCount=#mouseMoves
assert(not pointer(200,150,"mouse",nil,function() return true end,{X=200,Y=114},plannedPart))
assert(#mouseMoves==oldMoveCount and mouseClicks==beforeMismatch)
resetCursor();mousePosition={X=25,Y=30}
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
    RaycastParams={new=function() return {} end},Enum={RaycastFilterType={Exclude=1}},cursor3dUnsafe={mouse=false,virtual=false},
},{__index=_G})
local barrierSource=section("local function possibleBoardBarrier(obj)","-- WorldToViewportPoint")
retryEnv.possibleBoardBarrier,retryEnv.possibleCountHelper=assert(load(barrierSource.."\nreturn possibleBoardBarrier,possibleCountHelper","barrier","t",retryEnv))()
assert(load(retry,"retry","t",retryEnv))()
assert(not retryAdapter.retryPiece("Piece2_1") and count==0,"occluded piece must not be clicked")
assert(logs[#logs]=="RETRY_GUARD:raycast_other_object")
hit=piece;assert(retryAdapter.retryPiece("Piece2_1") and count==1,"visible piece may get one retry")
assert(selectedMethod=="mouse" and lastX==200 and lastY==150 and lastGuiPoint.Y==114,"viewport input differs from inset-relative GUI hit test")
assert(retryAdapter.retryPiece("Piece2_1",function() return true end,"virtual") and selectedMethod=="vim3d","explicit virtual retry uses the virtual pointer path")
count=count-1
-- Prefer the cursor; only fall back to touch when no mouse press started.
local methodOrder={}
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint)
    methodOrder[#methodOrder+1]=method;assert(valid())
    return method~="mouse"
end
assert(retryAdapter.retryPiece("Piece2_1") and #methodOrder==2 and methodOrder[1]=="mouse" and methodOrder[2]=="touch")
methodOrder={}
retryEnv.pointerClick=function(x,y,method)
    methodOrder[#methodOrder+1]=method;retryEnv.cursor3dUnsafe.mouse=true;return false
end
assert(not retryAdapter.retryPiece("Piece2_1") and #methodOrder==1 and methodOrder[1]=="mouse","bad cursor mapping suppresses touch fallback")
assert(not retryAdapter.retryPiece("Piece2_1",nil,"virtual") and methodOrder[2]=="vim3d","independent virtual backend remains eligible")
retryEnv.cursor3dUnsafe={mouse=false,virtual=false}
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
-- Only a table-sized, inert enclosure over all board corners is eligible;
-- a second ray must reach the intended object. The actual world is unmodified.
local tableModel,boardFolder,piecesFolder={},{},{}
function tableModel:FindFirstChild(name) return name=="Board" and boardFolder or name=="Pieces" and piecesFolder end
local grid={}
for r=1,8 do
    grid[r]={}
    for col=1,8 do grid[r][col]={Parent=boardFolder,Position=vec((col-1)*0.57,0,(r-1)*0.57)} end
end
local barrier={Parent=tableModel,Transparency=1,CanCollide=false,CanQuery=true,Anchored=true,
    Shape="block",Size=vec(7,10,14),CFrame={PointToObjectSpace=function(_,v) return vec(v.X-2, v.Y, v.Z-2) end}}
function barrier:IsA(k) return k=="Part" or k=="BasePart" end
function barrier:FindFirstChildWhichIsA() return nil end
retryEnv.Enum.PartType={Block="block"};retryEnv.model=tableModel;retryEnv.cells=grid
retryEnv.safeDescendant=function(o,ancestor)
    while o do if o==ancestor then return true end;o=o.Parent end
    return false
end
assert(retryEnv.possibleBoardBarrier(barrier),"geometric barrier may be examined")
barrier.Size=vec(1,1,1);assert(not retryEnv.possibleBoardBarrier(barrier),"small transparent object is not enclosure");barrier.Size=vec(7,10,14)
barrier.CanCollide=true;assert(not retryEnv.possibleBoardBarrier(barrier));barrier.CanCollide=false
barrier.Parent=piecesFolder;piecesFolder.Parent=tableModel
assert(not retryEnv.possibleBoardBarrier(barrier),"piece hitboxes are never barriers");barrier.Parent=tableModel
barrier.FindFirstChildWhichIsA=function() return {} end
assert(not retryEnv.possibleBoardBarrier(barrier),"interactive enclosure is not bypassed")
barrier.FindFirstChildWhichIsA=function() return nil end
boardFolder.Parent=tableModel
local second=piece
function world:Raycast(origin,direction,params)
    for _,item in ipairs(params.FilterDescendantsInstances) do if item==barrier then return second and {Instance=second} end end
    return {Instance=barrier}
end
local allowed
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint,targetPart,allowedBarrier)
    assert(valid());allowed=allowedBarrier
    assert(allowed(barrier) and not allowed(wall),"pointer may accept only verified barrier")
    count=count+1;return true
end
local beforeBarrier=count
assert(retryAdapter.retryPiece("Piece2_1") and count==beforeBarrier+1,"retry through candidate only when second ray reaches piece")
second=wall;assert(not retryAdapter.retryPiece("Piece2_1") and count==beforeBarrier+1,"second obstacle blocks input")
second=nil;assert(not retryAdapter.retryPiece("Piece2_1") and count==beforeBarrier+1,"missing target behind barrier blocks input")
second=piece
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint,targetPart,allowedBarrier)
    second=wall;assert(not valid(),"new obstacle cancels pending press");return false
end
assert(not retryAdapter.retryPiece("Piece2_1"),"recheck immediately before press")
-- Mouse.Target can only be the barrier already proven by the current ray.
actualTarget=barrier;local clicksBeforeBarrier=#clicks
assert(pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart,function(o) return o==barrier end))
assert(#clicks==clicksBeforeBarrier+2)
actualTarget=wall
assert(not pointer(200,150,"vim3d",nil,function() return true end,{X=200,Y=114},plannedPart,function(o) return o==barrier end),"other pointer target must still block")
world.Raycast=oldRay
-- A possible 1x1 PlayerCount is permitted only by exact table identity and
-- disabled noninteractive GUI; a similarly sized unknown part still blocks.
local functional={Parent=tableModel}
local countHelper={Parent=functional,Transparency=1,CanCollide=false,CanQuery=true,Anchored=true,Size=vec(1,1,1)}
function countHelper:IsA(k) return k=="Part" end
local countGui={Enabled=false};function countGui:IsA(k) return k=="BillboardGui" end
function countHelper:GetDescendants() return {countGui} end
function functional:FindFirstChild(n) if n=="PlayerCount" then return countHelper end end
function tableModel:FindFirstChild(name)
    if name=="Board" then return boardFolder elseif name=="Pieces" then return piecesFolder elseif name=="Functional" then return functional end
end
assert(retryEnv.possibleCountHelper(countHelper))
countGui.Enabled=true;assert(not retryEnv.possibleCountHelper(countHelper),"enabled GUI must block");countGui.Enabled=false
local detector={};function detector:IsA(k) return k=="ClickDetector" end
function countHelper:GetDescendants() return {countGui,detector} end
assert(not retryEnv.possibleCountHelper(countHelper),"interactive helper must block")
function countHelper:GetDescendants() return {countGui} end
local other={};assert(not retryEnv.possibleCountHelper(other),"unknown object is not the count helper")
second=piece
function world:Raycast(origin,direction,params)
    local skipped={};for _,o in ipairs(params.FilterDescendantsInstances) do skipped[o]=true end
    if not skipped[countHelper] then return {Instance=countHelper} end
    if not skipped[barrier] then return {Instance=barrier} end
    return second and {Instance=second}
end
retryEnv.pointerClick=function(x,y,method,expected,valid,guiPoint,targetPart,allowedBarrier)
    assert(method=="mouse" and valid())
    assert(allowedBarrier(countHelper) and allowedBarrier(barrier) and not allowedBarrier(wall))
    return true
end
assert(retryAdapter.retryPiece("Piece2_1"),"known helper and enclosure can be checked in either order")
second=wall;assert(not retryAdapter.retryPiece("Piece2_1"),"other objects behind helper still block")
countGui.Enabled=true;second=piece;assert(not retryAdapter.retryPiece("Piece2_1"),"enabled helper cannot be skipped")
world.Raycast=oldRay
-- Touch starts and ends even if Stop happens in the middle; GUI testing uses inset coordinates.
services.VirtualInputManager=vim;overlays={};shouldHide=true
local touchCalls={};local checkedX,checkedY
function pg:GetGuiObjectsAtPosition(x,y) checkedX,checkedY=x,y;return overlays end
function vim:SendTouchEvent(id,state,x,y) touchCalls[#touchCalls+1]={id,state,x,y} end
local beforeTouch=frames
waitHook=function() if frames==beforeTouch+2 then env.controller.running=false end end
assert(pointer(200,150,"touch",nil,function() return true end,{X=200,Y=114}),"touch should start")
waitHook=nil;assert(#touchCalls==2 and touchCalls[1][2]==0 and touchCalls[2][2]==2 and checkedX==200 and checkedY==114 and gui.Enabled,"touch release and inset GUI guard")
env.controller.running=true
io.write("PASS: vote pointer fallback, UI blocking guards, restoration and piece raycast retry\n")
