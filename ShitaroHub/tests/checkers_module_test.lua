-- Run the real UI integration and adapter against a minimal Roblox mock.
local function signal()
    local s={items={}}
    function s:Connect(fn)
        local x={fn=fn,enabled=true};self.items[#self.items+1]=x
        return {Disconnect=function() x.enabled=false end}
    end
    function s:Fire(...) for _,x in ipairs(self.items) do if x.enabled then x.fn(...) end end end
    return s
end
local vec={};vec.__index=function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
vec.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},vec) end
local function v(x,y,z) return setmetatable({X=x,Y=y,Z=z},vec) end
local O={};O.__index=O
function O:IsA(k)
    if self.ClassName==k then return true end
    if k=="BasePart" then return self.ClassName=="Part" or self.ClassName=="MeshPart" or self.ClassName=="Seat" end
    if k=="GuiButton" then return self.ClassName=="TextButton" or self.ClassName=="ImageButton" end
    return false
end
function O:FindFirstChild(n) for _,x in ipairs(self.children) do if x.Name==n then return x end end end
function O:FindFirstChildOfClass(n) for _,x in ipairs(self.children) do if x:IsA(n) then return x end end end
function O:GetChildren() return self.children end
function O:GetAttribute(k) return self.attrs[k] end
local function new(class,name,parent,props)
    local x=setmetatable({ClassName=class,Name=name,Parent=parent,children={},attrs={},Activated=signal(),MouseButton1Click=signal()},O)
    for k,val in pairs(props or {}) do x[k]=val end
    if parent then parent.children[#parent.children+1]=x end
    return x
end
function typeof(x) return getmetatable(x)==O and "Instance" or type(x) end
UDim2={fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end,new=function(...) return {...} end}
UDim={new=function(...) return {...} end}
Color3={fromRGB=function(...) return {...} end}
Enum={TextXAlignment={Center=1},HighlightDepthMode={AlwaysOnTop=1}}
local originalClock,originalInstance=os.clock,Instance
local mockTime=0;os.clock=function() return mockTime end
local highlights={}
Instance={new=function(class)
    assert(class=="Highlight")
    local mark={ClassName=class};function mark:Destroy() self.destroyed=true end
    highlights[#highlights+1]=mark;return mark
end}
local world=new("Workspace","Workspace")
local rep=new("ReplicatedStorage","ReplicatedStorage")
local remote=new("RemoteEvent","GameEvent",rep);remote.OnClientEvent=signal()
local votes=new("RemoteEvent","ModeVoteEvent",rep);votes.OnClientEvent=signal()
local localPlayer=new("Player","Me");localPlayer.UserId=42
local pg=new("PlayerGui","PlayerGui",localPlayer)
local char=new("Model","Char",world);localPlayer.Character=char
local hrp=new("Part","HumanoidRootPart",char,{Position=v(2,2,2)})
local hum=new("Humanoid","Humanoid",char,{Health=100})
function hum:MoveTo(pos) self.lastMove=pos end
local tabRoot=new("Model","Game1",world)
local seat1=new("Seat","Seat1",tabRoot,{Position=v(2,0,0)})
local seat2=new("Seat","Seat2",tabRoot,{Position=v(2,0,5),Occupant=hum});hum.SeatPart=seat2
local board=new("Folder","Board",tabRoot);local pieces=new("Folder","Pieces",tabRoot)
local initial={};for r=1,8 do initial[r]={} end
local number={0,0}
for r=1,8 do for col=1,8 do
    local dark=(r+col)%2==1
    local tile=new("Part",dark and "Move" or "BlockMove",board,{Position=v(col,0,r)})
    new("ClickDetector","ClickDetector",tile,{MaxActivationDistance=32})
    if dark and (r<=3 or r>=6) then
        local side=r<=3 and 2 or 1;number[side]=number[side]+1
        local id="Piece"..side.."_"..number[side]
        initial[r][col]={side=side,id=id,king=false}
        local piece=new("MeshPart",id,pieces,{Position=v(col,0,r)})
        local hit=new("Part","ClickHitbox",piece,{Position=v(col,0,r)})
        new("ClickDetector","ClickDetector",hit,{MaxActivationDistance=20})
    end
end end
local modeGui=new("ScreenGui","ModeSelectGui",pg,{Enabled=true})
local panel=new("Frame","Panel",modeGui)
new("ImageButton","AmericanButton",panel,{Visible=true,AbsoluteSize={X=100,Y=50},AbsolutePosition={X=50,Y=50}})
new("ImageButton","ClassicButton",panel,{Visible=true,AbsoluteSize={X=100,Y=50},AbsolutePosition={X=200,Y=50}})
local activeGui=new("ScreenGui","ShitaroMenuOnly",pg)
local window=new("Frame","Menu",activeGui,{Visible=true})
local page=new("Frame","checkers",window)
local players={LocalPlayer=localPlayer}
local services={Workspace=world,ReplicatedStorage=rep,HttpService={},UserInputService={},RunService={RenderStepped={Wait=function() end}}}
game={PlaceId=75526590957446};function game:GetService(n) return assert(services[n]) end
local clicks,voteCalls={},0
function fireclickdetector(d) clicks[#clicks+1]=d end
function getconnections() return {{Enabled=true,Fire=function() voteCalls=voteCalls+1 end}} end
isfile=nil;readfile=nil;writefile=nil
local logEnv,clipboard={},nil
function getgenv() return logEnv end
function setclipboard(value) clipboard=value end
local co;task={}
function task.spawn(f) co=coroutine.create(f);assert(coroutine.resume(co)) end
function task.wait() coroutine.yield() end
local function step() mockTime=mockTime+0.25;local ok,err=coroutine.resume(co);assert(ok,err) end
local loader={}
function loader.module(path) return assert(loadfile(path))() end
local hideCount=0
local ctx={Players=players,player=localPlayer,playerGui=pg,gui=activeGui,Loader=loader,tabs={[7]={page=page}},
    colors={text=1},corner=function() end,hideMenu=function() hideCount=hideCount+1;window.Visible=false end,
    make=function(class,props,parent) return new(class,props.Name or class,parent,props) end,
    connect=function(s,f) return s:Connect(f) end}
assert(loadfile("modules/checkers.lua"))()(ctx)
local main=assert(page:FindFirstChild("CheckersBot"))
local stats=assert(page:FindFirstChild("CheckersStatistics"))
local hud=assert(activeGui:FindFirstChild("CheckersHUD"));assert(hud.Visible==false,"HUD hidden before start")
local hudStatus=assert(hud:FindFirstChild("Status"));local hudAction=assert(hud:FindFirstChild("Action"));local hudTurn=assert(hud:FindFirstChild("Turn"))
local hudStop=assert(hud:FindFirstChild("Stop"));local hudCopy=assert(hud:FindFirstChild("CopyLog"))
local start=assert(main:FindFirstChild("Start"));local stop=assert(main:FindFirstChild("Stop"))
local statsButton=assert(main:FindFirstChild("Statistics"))
assert(#clicks==0,"bot must be disabled on load")
local clickApi=fireclickdetector;fireclickdetector=nil
start.Activated:Fire();step();assert(#clicks==0 and main:FindFirstChild("Status").Text:find("fireclickdetector",1,true),"start refuses missing executor capability")
assert(hud.Visible and hudStatus.Text:find("fireclickdetector",1,true) and hideCount==0,"failed start stays visible and does not hide menu")
fireclickdetector=clickApi
start.Activated:Fire()
assert(hud.Visible and not window.Visible and hideCount==1,"valid start hides window but leaves HUD visible")
assert(hudStatus.Text=="Поиск стола" and hudAction.Text=="Поиск стола")
hudCopy.Activated:Fire();assert(clipboard and clipboard:find("manual_copy",1,true),"HUD copies log")
votes.OnClientEvent:Fire("Start",{{userId=42}},15)
step();assert(voteCalls==1,"one local vote")
assert(hudAction.Text=="Пытаюсь проголосовать","HUD shows voting")
votes.OnClientEvent:Fire("Voted",42,"American")
assert(hudStatus.Text:find("Голос подтверждён",1,true),"HUD must show server-confirmed vote")
votes.OnClientEvent:Fire("Result","Classic",true)
assert(hudStatus.Text:find("Classic",1,true),"HUD must show actual rule result")
remote.OnClientEvent:Fire("GameStarted")
remote.OnClientEvent:Fire("TurnChanged",localPlayer,{})
remote.OnClientEvent:Fire("YourTurn",35)
step();assert(hudTurn.Text:find("Ваш ход",1,true) and hudTurn.Text:find("Classic",1,true),"HUD shows turn and rules")
step();step()
assert(#clicks==1,"must select exactly one piece")
local selected=clicks[1].Parent.Parent.Name
local e=assert(loadfile("core/checkers_engine.lua"))()
local options={}
for _,m in ipairs(e.moves(initial,2,"Classic")) do
    if initial[m.r][m.c].id==selected then
        local st=m.steps[1];options[#options+1]={row=st.r,col=st.c,isCapture=st.cr~=nil}
    end
end
assert(#options>0)
remote.OnClientEvent:Fire("PieceSelected",selected,options)
step();assert(#clicks==2,"must click a server-confirmed destination")
local pos=clicks[2].Parent.Position
remote.OnClientEvent:Fire("PieceMoved",selected,pos.Z,pos.X,nil,false)
remote.OnClientEvent:Fire("GameOver",localPlayer,true)
assert(clipboard and clipboard==logEnv.ShitaroCheckersBotLog,"game end must copy the log")
assert(clipboard:find("GAME GameOver winner=local",1,true) and clipboard:find("SELECT_ATTEMPT",1,true),"log includes actions and game events")
assert(not clipboard:find("Me",1,true) and not clipboard:find("UserId=42",1,true),"log must not expose player identifiers")
statsButton.Activated:Fire()
assert(stats.Visible and stats:FindFirstChild("Stats").Text:find("Побед: 1",1,true),"stats screen win")
hudStop.Activated:Fire();step();assert(#clicks==2,"no more actions after HUD stop")
assert(hud.Visible and hudStatus.Text=="Остановлен" and hudAction.Text=="Бот не действует","HUD persists after stop")
-- Real module integration: a failed automatic retry highlights the planned
-- piece; a manual server-confirmed selection lets the bot click its cell.
start.Activated:Fire();votes.OnClientEvent:Fire("Start",{{userId=42}},15)
votes.OnClientEvent:Fire("Result","Classic",true);remote.OnClientEvent:Fire("GameStarted")
remote.OnClientEvent:Fire("TurnChanged",localPlayer,{});remote.OnClientEvent:Fire("YourTurn",35)
step();step();step();local guided=clicks[#clicks].Parent.Parent.Name
for i=1,10 do step() end
local mark=assert(highlights[#highlights],"failed automatic selection creates a visual guide")
assert(mark.Adornee.Name==guided and mark.Parent==mark.Adornee and hudStatus.Text=="Нажмите подсвеченную шашку")
local guidedOptions={}
for _,m in ipairs(e.moves(initial,2,"Classic")) do
    if initial[m.r][m.c].id==guided then
        local st=m.steps[1];guidedOptions[#guidedOptions+1]={row=st.r,col=st.c,isCapture=st.cr~=nil}
    end
end
local beforeGuidedCell=#clicks
remote.OnClientEvent:Fire("PieceSelected",guided,guidedOptions)
assert(mark.destroyed,"manual confirmation clears highlight")
step();assert(#clicks==beforeGuidedCell+1,"server-confirmed manual piece selection advances to cell")
hudStop.Activated:Fire()
-- An unexpected server selection stops safely and leaves its reason on the HUD.
start.Activated:Fire();votes.OnClientEvent:Fire("Start",{{userId=42}},15)
votes.OnClientEvent:Fire("Result","American",false);remote.OnClientEvent:Fire("GameStarted")
remote.OnClientEvent:Fire("TurnChanged",localPlayer,{});step();step();step()
assert(hudAction.Text=="Шашка найдена; жду ответ игры","HUD displays pending selection")
remote.OnClientEvent:Fire("PieceSelected","Piece1_999",{{row=1,col=1,isCapture=false}})
assert(hud.Visible and hudStatus.Text:find("Остановлен",1,true) and hudAction.Text=="Бот не действует","HUD retains halt reason")
hudCopy.Activated:Fire();assert(hudCopy.Text=="Скопировано" and clipboard:find("HALT",1,true),"HUD copies halt log")
-- When standing, prefer the empty seat opposite an occupied chair and cancel
-- any movement the bot initiated when the user presses Stop.
hum.SeatPart=nil;seat2.Occupant=nil;seat1.Occupant=new("Humanoid","Opponent")
hrp.Position=v(2,2,0);hum.lastMove=nil
start.Activated:Fire();step()
assert(hum.lastMove==seat2.Position,"bot should walk to available seat opposite a player")
stop.Activated:Fire();assert(hum.lastMove==hrp.Position,"stop cancels bot movement")
-- The opposite chair maps to side one; server confirmation is still required.
hum.SeatPart=seat1;seat1.Occupant=hum;seat2.Occupant=new("Humanoid","Opponent2")
start.Activated:Fire();votes.OnClientEvent:Fire("Start",{{userId=42}},15)
votes.OnClientEvent:Fire("Result","Classic",true);remote.OnClientEvent:Fire("GameStarted")
remote.OnClientEvent:Fire("TurnChanged",localPlayer,{})
step();step();step();assert(clicks[#clicks].Parent.Parent.Name:match("^Piece1_"),"Seat1 should select side one")
stop.Activated:Fire()
-- Destroying the UI while a move is planned must not execute the next tick.
hum.SeatPart=seat2;seat2.Occupant=hum;hrp.Position=v(2,2,2)
start.Activated:Fire();votes.OnClientEvent:Fire("Start",{{userId=42}},15)
votes.OnClientEvent:Fire("Result","American",false);remote.OnClientEvent:Fire("GameStarted")
remote.OnClientEvent:Fire("TurnChanged",localPlayer,{})
step();step();local beforeClose=#clicks
activeGui.Parent=nil;step();assert(#clicks==beforeClose,"closing UI must not execute another action")
os.clock=originalClock;Instance=originalInstance
io.write("PASS: actual checkers module, GUI, guided selection, confirmed clicks, stats and stop\n")
