-- Experimental checkers integration. Never acts until Start is pressed.
return function(ctx)
if game.PlaceId ~= 75526590957446 or not ctx.tabs[7] then return end
local Players, Workspace = ctx.Players, game:GetService("Workspace")
local ReplicatedStorage, HttpService = game:GetService("ReplicatedStorage"), game:GetService("HttpService")
local player, playerGui, gui = ctx.player, ctx.playerGui, ctx.gui
local make, connect, corner = ctx.make, ctx.connect, ctx.corner
local okEngine, engine = pcall(ctx.Loader.module, "core/checkers_engine.lua")
local okController, createController = pcall(ctx.Loader.module, "core/checkers_controller.lua")
if not okEngine or not okController then error("checkers modules unavailable") end

local page = ctx.tabs[7].page
local function text(parent,name,textValue,y,height)
    return make("TextLabel",{Name=name,Text=textValue,TextSize=14,TextWrapped=true,
        Position=UDim2.fromOffset(16,y),Size=UDim2.new(1,-32,0,height),
        TextColor3=ctx.colors.text},parent)
end
local function button(parent,name,title,x,y,width)
    local b=make("TextButton",{Name=name,Text=title,TextSize=14,
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,34),
        BackgroundTransparency=0,BackgroundColor3=Color3.fromRGB(52,41,64),
        TextColor3=Color3.fromRGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Center},parent)
    corner(b,UDim.new(0,6));return b
end
local main=make("Frame",{Name="CheckersBot",Size=UDim2.fromScale(1,1)},page)
local statPage=make("Frame",{Name="CheckersStatistics",Size=UDim2.fromScale(1,1),Visible=false},page)
text(main,"Heading","Шашки — экспериментальный бот",10,24)
local stateLabel=text(main,"Status","Остановлен",48,48)
local clockLabel=text(main,"Time","",100,28)
local startButton=button(main,"Start","Start",16,140,100)
local stopButton=button(main,"Stop","Stop",126,140,100)
local statsButton=button(main,"Statistics","Статистика",236,140,128)
text(main,"Help","Запустите до посадки. Бот ожидает итог голосования и подтверждение ходов игры. При ошибке он останавливается.",190,76)
text(statPage,"Heading","Статистика игр бота",10,24)
local statsLabel=text(statPage,"Stats","",50,120)
local backButton=button(statPage,"Back","Назад",16,190,100)

local model, cells, moving, lastSeatAttempt = nil, nil, false, -math.huge
local statsPath="ShitaroHub/checkers_stats_"..tostring(player.UserId)..".json"
local persistence=false
local function loadStats()
    if type(readfile)~="function" or type(writefile)~="function" or type(isfile)~="function" then return nil end
    local ok,exists=pcall(isfile,statsPath);if not ok then return nil end
    if not exists then persistence=true;return nil end
    local readOk,body=pcall(readfile,statsPath);if not readOk then return nil end
    local decodedOk,data=pcall(function() return HttpService:JSONDecode(body) end)
    if not decodedOk or type(data)~="table" then return nil end
    for _,k in ipairs({"games","wins","losses","unknown"}) do
        if type(data[k])~="number" or data[k]<0 or data[k]%1~=0 or data[k]>10000000 then return nil end
    end
    if data.wins+data.losses+data.unknown~=data.games then return nil end
    persistence=true;return data
end
local savedStats=loadStats()
local adapter={}
adapter.now=os.clock
local function humanoid()
    return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end
local function seatContext()
    local hum=humanoid();local seat=hum and hum.SeatPart
    if not seat or not seat.Parent or (seat.Name~="Seat1" and seat.Name~="Seat2") then return nil end
    local root=seat.Parent
    if not root:FindFirstChild("Board") then return nil end
    return root,seat,seat.Name=="Seat1" and 1 or 2
end
function adapter.isSeated()
    local root=seatContext()
    if root then moving=false end
    return root~=nil and (model==nil or model==root)
end
function adapter.seatKey() return seatContext() end
function adapter.releaseBoard() model=nil;cells=nil end
function adapter.cancel()
    if moving then
        local hum=humanoid();local char=player.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if hum and root then pcall(function() hum:MoveTo(root.Position) end) end
    end
    moving=false
end
function adapter.seekSeat()
    local hum=humanoid();local char=player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health<=0 or hum.SeatPart then return end
    local best, bestScore
    for _,candidate in ipairs(Workspace:GetChildren()) do
        local board=candidate:FindFirstChild("Board")
        if board then
            for _,seatName in ipairs({"Seat1","Seat2"}) do
                local seat=candidate:FindFirstChild(seatName)
                local other=candidate:FindFirstChild(seatName=="Seat1" and "Seat2" or "Seat1")
                if seat and seat:IsA("Seat") and not seat.Occupant
                    and seat:GetAttribute("SeatLockActive")~=true and other and other:IsA("Seat") then
                    local dist=(seat.Position-root.Position).Magnitude
                    local score=dist-(other.Occupant and 1000 or 0)
                    if not best or score<bestScore then best,bestScore=seat,score end
                end
            end
        end
    end
    if not best then return end
    local distance=(best.Position-root.Position).Magnitude
    moving=true
    pcall(function() hum:MoveTo(best.Position) end)
    if distance<4 and not best.Occupant and os.clock()-lastSeatAttempt>2 then
        lastSeatAttempt=os.clock();pcall(function() best:Sit(hum) end)
    end
end
function adapter.containsLocal(list)
    if type(list)~="table" then return false end
    for _,entry in pairs(list) do if type(entry)=="table" and entry.userId==player.UserId then return true end end
    return false
end
function adapter.isLocalId(id) return id==player.UserId end
function adapter.isLocal(p) return p==player end
function adapter.result(p)
    if p==player then return "win" end
    if typeof(p)=="Instance" and p:IsA("Player") then return "loss" end
    return "unknown"
end
function adapter.saveStats(stats)
    if not persistence then return end
    local ok=pcall(function()
        if type(makefolder)=="function" and type(isfolder)=="function" and not isfolder("ShitaroHub") then makefolder("ShitaroHub") end
        writefile(statsPath,HttpService:JSONEncode(stats))
    end)
    if not ok then persistence=false end
end
-- No direct remote calls: invoke available local GUI event connections and
-- wait for the server's Voted/Result messages. Unsupported executors can vote manually.
function adapter.vote(mode)
    if type(getconnections)~="function" then return false end
    local screen=playerGui:FindFirstChild("ModeSelectGui")
    local panel=screen and screen:FindFirstChild("Panel")
    local b=panel and panel:FindFirstChild(mode=="American" and "AmericanButton" or "ClassicButton")
    if not b or not b:IsA("GuiButton") or not b.Visible or not screen.Enabled then return false end
    for _,name in ipairs({"MouseButton1Click","Activated"}) do
        local ok,list=pcall(function() return getconnections(b[name]) end)
        if ok and type(list)=="table" and #list>0 then
            local fired=false
            for _,link in ipairs(list) do
                local done=pcall(function()
                    if link.Enabled==false then return end
                    if type(link.Fire)=="function" then link:Fire();fired=true
                    elseif type(link.Function)=="function" then link.Function();fired=true end
                end)
                if not done then return false end
            end
            if fired then return true end
        end
    end
    return false
end
local function uniqueSorted(values)
    table.sort(values)
    local result={}
    for _,v in ipairs(values) do if #result==0 or math.abs(v-result[#result])>0.08 then result[#result+1]=v end end
    return result
end
local function indexNear(values,value)
    local best,dist
    for i,v in ipairs(values) do local d=math.abs(v-value);if not dist or d<dist then best,dist=i,d end end
    return best,dist
end
function adapter.initialBoard()
    local root,_,side=seatContext();if not root then return nil end
    local folder=root:FindFirstChild("Board");local pieces=root:FindFirstChild("Pieces")
    if not folder or not pieces then return nil end
    local tiles,x,z={}, {}, {}
    for _,o in ipairs(folder:GetChildren()) do
        if o:IsA("BasePart") and (o.Name=="Move" or o.Name=="BlockMove") then
            tiles[#tiles+1]=o;x[#x+1]=o.Position.X;z[#z+1]=o.Position.Z
        end
    end
    x,z=uniqueSorted(x),uniqueSorted(z)
    if #tiles~=64 or #x~=8 or #z~=8 then return nil end
    local dx,dz=x[2]-x[1],z[2]-z[1]
    if dx<0.2 or dz<0.2 or math.abs(dx-dz)>0.1 then return nil end
    for i=2,8 do
        if math.abs((x[i]-x[i-1])-dx)>0.06 or math.abs((z[i]-z[i-1])-dz)>0.06 then return nil end
    end
    local tileGrid={};for r=1,8 do tileGrid[r]={} end
    for _,o in ipairs(tiles) do
        local row,dr=indexNear(z,o.Position.Z);local col,dc=indexNear(x,o.Position.X)
        if not row or dr>0.08 or dc>0.08 or tileGrid[row][col] then return nil end
        tileGrid[row][col]=o
    end
    local board={};for r=1,8 do board[r]={} end
    local count=0;local perSide={0,0}
    for _,o in ipairs(pieces:GetChildren()) do
        local team=o.Name:match("^Piece([12])_%d+$")
        if team and o:IsA("BasePart") then
            team=tonumber(team)
            local row,dr=indexNear(z,o.Position.Z);local col,dc=indexNear(x,o.Position.X)
            -- Initial positions only: never infer a mid-game board or a moving piece.
            if not row or dr>0.12 or dc>0.12 or board[row][col] or
                (team==2 and row>3) or (team==1 and row<6) then return nil end
            board[row][col]={side=team,id=o.Name,king=false};count=count+1;perSide[team]=perSide[team]+1
        end
    end
    if count~=24 or perSide[1]~=12 or perSide[2]~=12 then return nil end
    model=root;cells=tileGrid;moving=false
    return board,side
end
local function clickDetector(detector)
    if not detector or not detector.Parent then return nil end
    if type(fireclickdetector)~="function" then return false end
    local max=detector.MaxActivationDistance
    if type(max)~="number" or max<=0 then return nil end
    local hum=humanoid();local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local part=detector.Parent
    if not hum or not root or not part:IsA("BasePart") then return false end
    if (part.Position-root.Position).Magnitude>max then return nil end
    local ok=pcall(fireclickdetector,detector)
    return ok
end
function adapter.selectPiece(id)
    if not model or not adapter.isSeated() then return false end
    local folder=model:FindFirstChild("Pieces");local part=folder and folder:FindFirstChild(id)
    if not part or not part:IsA("BasePart") then return false end
    local hitbox=part:FindFirstChild("ClickHitbox")
    local detector=hitbox and hitbox:FindFirstChildOfClass("ClickDetector") or part:FindFirstChildOfClass("ClickDetector")
    return clickDetector(detector)
end
function adapter.clickCell(row,col)
    if not model or not cells or not adapter.isSeated() then return false end
    local part=cells[row] and cells[row][col]
    if not part or not part.Parent or part.Name~="Move" then return false end
    return clickDetector(part:FindFirstChildOfClass("ClickDetector"))
end
local controller=createController(engine,adapter)
if savedStats then for _,k in ipairs({"games","wins","losses","unknown"}) do controller.stats[k]=savedStats[k] end end
local function refresh()
    stateLabel.Text=controller.status
    local remaining=controller.timeLeft()
    clockLabel.Text=(controller.mode and ("Правила: "..controller.mode.."   ") or "")..(remaining and ("Осталось: "..remaining.." сек.") or "")
    local s=controller.stats
    statsLabel.Text="Игр: "..s.games.."\nПобед: "..s.wins.."\nПоражений: "..s.losses.."\nНеизвестный результат: "..s.unknown.."\n"..(persistence and "Статистика сохраняется локально" or "Только текущая сессия")
end
adapter.changed=refresh
local gameLink,voteLink
local function ensureListeners()
    if gameLink and voteLink then return true end
    local event=ReplicatedStorage:FindFirstChild("GameEvent")
    local vote=ReplicatedStorage:FindFirstChild("ModeVoteEvent")
    if not event or not vote or not event:IsA("RemoteEvent") or not vote:IsA("RemoteEvent") then return false end
    gameLink=event.OnClientEvent:Connect(function(...) local ok,err=pcall(controller.event,...);if not ok then controller.stop();warn("[checkers] event error: "..tostring(err)) end end)
    voteLink=vote.OnClientEvent:Connect(function(...) local ok,err=pcall(controller.vote,...);if not ok then controller.stop();warn("[checkers] vote error: "..tostring(err)) end end)
    return true
end
connect(startButton.Activated,function()
    if controller.running then return end
    if type(fireclickdetector)~="function" then stateLabel.Text="Нет fireclickdetector — бот не запущен";return end
    if not ensureListeners() then stateLabel.Text="Игровые события не найдены — бот не запущен";return end
    controller.start()
end)
connect(stopButton.Activated,function() controller.stop();refresh() end)
connect(statsButton.Activated,function() main.Visible=false;statPage.Visible=true;refresh() end)
connect(backButton.Activated,function() statPage.Visible=false;main.Visible=true end)
refresh()
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        if not gui.Parent then break end
        if controller.running then
            local ok,err=pcall(controller.tick)
            if not ok then controller.stop();stateLabel.Text="Ошибка; бот остановлен";warn("[checkers] "..tostring(err)) end
            refresh()
        end
    end
    controller.stop()
    if gameLink then gameLink:Disconnect() end
    if voteLink then voteLink:Disconnect() end
end)
end
