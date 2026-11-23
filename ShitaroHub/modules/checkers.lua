-- Experimental checkers integration. Never acts until Start is pressed.
return function(ctx)
if game.PlaceId ~= 75526590957446 or not ctx.tabs[7] then return end
local Players, Workspace = ctx.Players, game:GetService("Workspace")
local ReplicatedStorage, HttpService = game:GetService("ReplicatedStorage"), game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player, playerGui, gui = ctx.player, ctx.playerGui, ctx.gui
local make, connect, corner = ctx.make, ctx.connect, ctx.corner
local okEngine, engine = pcall(ctx.Loader.module, "core/checkers_engine.lua")
local okController, createController = pcall(ctx.Loader.module, "core/checkers_controller.lua")
local okLog, createLog = pcall(ctx.Loader.module, "core/checkers_log.lua")
if not okEngine or not okController or not okLog then error("checkers modules unavailable") end

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
local copyButton=button(main,"CopyLog","Копировать лог",16,183,160)
local logLabel=text(main,"LogStatus","Лог сохраняется при остановке или окончании партии",220,32)
text(main,"Help","Запустите до посадки. Бот ожидает итог голосования и подтверждение ходов игры. При ошибке он останавливается.",255,65)
text(statPage,"Heading","Статистика игр бота",10,24)
local statsLabel=text(statPage,"Stats","",50,120)
local backButton=button(statPage,"Back","Назад",16,190,100)

-- A sibling of the menu window: remains visible when the window is hidden.
-- Only the two small buttons receive input, never a full-screen overlay.
local hud=make("Frame",{Name="CheckersHUD",Visible=false,Active=false,
    Position=UDim2.new(1,-226,0,48),Size=UDim2.fromOffset(218,162),
    BackgroundTransparency=0.12,BackgroundColor3=Color3.fromRGB(28,24,36),ZIndex=30},gui)
corner(hud,UDim.new(0,8))
local hudTitle=make("TextLabel",{Name="Heading",Text="Шашки · бот",TextSize=14,
    Position=UDim2.fromOffset(8,4),Size=UDim2.new(1,-16,0,20),ZIndex=31,Active=false},hud)
local hudStatus=make("TextLabel",{Name="Status",Text="Остановлен",TextSize=13,TextWrapped=true,
    Position=UDim2.fromOffset(8,25),Size=UDim2.new(1,-16,0,40),ZIndex=31,Active=false},hud)
local hudAction=make("TextLabel",{Name="Action",Text="",TextSize=12,TextWrapped=true,
    Position=UDim2.fromOffset(8,64),Size=UDim2.new(1,-16,0,26),ZIndex=31,Active=false},hud)
local hudTime=make("TextLabel",{Name="Turn",Text="",TextSize=12,TextWrapped=true,
    Position=UDim2.fromOffset(8,91),Size=UDim2.new(1,-16,0,25),ZIndex=31,Active=false},hud)
local hudStop=button(hud,"Stop","Stop",8,122,93);hudStop.ZIndex=32
local hudCopy=button(hud,"CopyLog","Копировать лог",108,122,102);hudCopy.ZIndex=32;hudCopy.TextSize=11

local model, cells, moving, lastSeatAttempt = nil, nil, false, -math.huge
local logger, lastStatus, controller
local copyFeedbackUntil=0
local env=(getgenv and getgenv()) or _G
local function log(kind,message)
    if logger then pcall(logger.add,kind,message) end
end
local function saveLog(reason)
    if not logger then logLabel.Text="Лог появится после Start";return false end
    log("SAVE",reason)
    local report=logger.report()
    env.ShitaroCheckersBotLog=report
    local fileOk=false
    if type(writefile)=="function" then
        fileOk=pcall(function()
            if type(makefolder)=="function" then
                for _,dir in ipairs({"ShitaroHub","ShitaroHub/diagnostics"}) do
                    if type(isfolder)~="function" or not isfolder(dir) then
                        local ok,err=pcall(makefolder,dir)
                        if not ok and (type(isfolder)~="function" or not isfolder(dir)) then error(err) end
                    end
                end
            end
            writefile("ShitaroHub/diagnostics/checkers_bot_log.txt",report)
        end)
    end
    local copy=type(setclipboard)=="function" and setclipboard or (type(toclipboard)=="function" and toclipboard or nil)
    local copyOk=false;if copy then copyOk=pcall(copy,report) end
    logLabel.Text=copyOk and "Лог скопирован в буфер" or (fileOk and "Буфер недоступен; лог сохранён в файл" or "Лог доступен в getgenv().ShitaroCheckersBotLog")
    if not copyOk and not fileOk then warn("[checkers] clipboard and file unavailable; log in getgenv().ShitaroCheckersBotLog") end
    return copyOk or fileOk,copyOk
end
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
adapter.trace=log
adapter.onStop=function(reason) saveLog("stop="..tostring(reason)) end
adapter.onRound=function() saveLog("game_over") end
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
-- A real pointer click is attempted only at a visible vote button, or at a
-- piece verified by raycast. The hub is hidden during injection so it does not
-- intercept the click. Nothing is sent via a guessed RemoteEvent protocol.
local function safeSignalVote(b)
    if type(getconnections)~="function" then log("VOTE_METHOD","getconnections unavailable");return false end
    for _,name in ipairs({"MouseButton1Click","Activated"}) do
        local ok,list=pcall(function() return getconnections(b[name]) end)
        local count=ok and type(list)=="table" and #list or 0
        log("VOTE_CONNECTIONS",name.." count="..count)
        if count>0 then
            local fired=false
            for _,link in ipairs(list) do
                local done=pcall(function()
                    if link.Enabled==false then return end
                    if type(link.Fire)=="function" then link:Fire();fired=true
                    elseif type(link.Function)=="function" then link.Function();fired=true end
                end)
                if not done then log("VOTE_CONNECTIONS","handler failed");return false end
            end
            if fired then return true end
        end
    end
    return false
end
local function safeDescendant(obj,ancestor)
    local ok,result=pcall(function() return obj:IsDescendantOf(ancestor) end)
    return ok and result==true
end
local function guiHitSafe(x,y,expected)
    local ok,objects=pcall(function() return playerGui:GetGuiObjectsAtPosition(x,y) end)
    if not ok or type(objects)~="table" then
        -- Never send a physical click through unexamined UI.
        log("INPUT_GUARD","GUI hit test unavailable");return false
    end
    local found=false
    for _,obj in ipairs(objects) do
        local within=expected and (obj==expected or safeDescendant(obj,expected))
        if within then found=true end
        if obj.Visible and obj.Active and not within then
            log("INPUT_GUARD","active UI covers target");return false
        end
        if found then break end
    end
    if expected and not found then log("INPUT_GUARD","button not at intended point");return false end
    return true
end
local inputBusy=false
local function pointerClick(x,y,method,expected,stillPending)
    if inputBusy or not controller or not controller.running then return false end
    local camera=Workspace.CurrentCamera
    if not camera or type(x)~="number" or type(y)~="number" then return false end
    local size=camera.ViewportSize
    if not size or x<0 or y<0 or x>=size.X or y>=size.Y then log("INPUT_GUARD","outside viewport");return false end
    inputBusy=true
    local oldEnabled=gui.Enabled
    local ok,result=pcall(function()
        gui.Enabled=false
        -- Let rendering and hit-testing actually update before injecting. The
        -- hub has DisplayOrder 10000, so toggling it only for the same Lua
        -- frame can still leave its window in the engine's input snapshot.
        RunService.RenderStepped:Wait()
        if not controller.running or (stillPending and not stillPending()) then
            log("INPUT_GUARD","action no longer pending");return false
        end
        if not guiHitSafe(x,y,expected) then return false end
        if method=="mouse" then
            if type(mousemoveabs)~="function" or (type(mouse1click)~="function" and (type(mouse1press)~="function" or type(mouse1release)~="function")) then return false end
            local got,old=pcall(function() return UserInputService:GetMouseLocation() end)
            local moved=pcall(mousemoveabs,math.floor(x),math.floor(y))
            if not moved then return false end
            local clicked
            if type(mouse1click)=="function" then clicked=pcall(mouse1click)
            else
                local down=pcall(mouse1press);local up=pcall(mouse1release)
                clicked=down and up
            end
            if got and old then pcall(mousemoveabs,old.X,old.Y) end
            log("INPUT", "mouse click invoked="..tostring(clicked))
            return clicked
        end
        local got,vim=pcall(function() return game:GetService("VirtualInputManager") end)
        if not got or not vim then return false end
        local down=pcall(function() vim:SendMouseButtonEvent(x,y,0,true,game,0) end)
        if down then pcall(function() RunService.RenderStepped:Wait() end) end
        -- Always release a pressed button, even if Stop or acknowledgement
        -- arrived while waiting. Never try another input after a partial down.
        local up=pcall(function() vim:SendMouseButtonEvent(x,y,0,false,game,0) end)
        log("INPUT", "virtual click down="..tostring(down).." up="..tostring(up))
        return down
    end)
    pcall(function() gui.Enabled=oldEnabled end)
    inputBusy=false
    if not ok then log("INPUT","click raised an error");return false end
    return result==true
end
local function clickVoteButton(b,screen,method,stillPending)
    local ok,x,y=pcall(function()
        local pos,size=b.AbsolutePosition,b.AbsoluteSize
        if size.X<=1 or size.Y<=1 then error("empty button") end
        return pos.X+size.X/2,pos.Y+size.Y/2
    end)
    if not ok then log("VOTE_METHOD","button bounds unavailable");return false end
    local function valid()
        if stillPending and not stillPending() then return false end
        if not screen.Enabled or not b.Visible then return false end
        local pos,size=b.AbsolutePosition,b.AbsoluteSize
        return size.X>1 and size.Y>1 and math.abs(pos.X+size.X/2-x)<1 and math.abs(pos.Y+size.Y/2-y)<1
    end
    return pointerClick(x,y,method,b,valid)
end
function adapter.vote(mode,attempt,stillPending)
    if not controller or not controller.running then return false end
    local screen=playerGui:FindFirstChild("ModeSelectGui")
    local panel=screen and screen:FindFirstChild("Panel")
    local b=panel and panel:FindFirstChild(mode=="American" and "AmericanButton" or "ClassicButton")
    if not b or not b:IsA("GuiButton") or not b.Visible or not screen.Enabled then
        log("VOTE_BUTTON","not ready");return nil
    end
    local sized=pcall(function() assert(b.AbsoluteSize.X>1 and b.AbsoluteSize.Y>1) end)
    if not sized then log("VOTE_BUTTON","waiting for layout");return nil end
    -- An injected click is not proof; only a Voted event confirms a vote.
    local methods=attempt==1 and {"vim","mouse","connections"}
        or (attempt==2 and {"mouse","connections","vim"} or {"connections","vim","mouse"})
    for _,method in ipairs(methods) do
        if not controller.running or (stillPending and not stillPending()) then return false end
        local fired=method=="connections" and safeSignalVote(b) or (method~="connections" and clickVoteButton(b,screen,method,stillPending))
        log("VOTE_METHOD",method.." attempted="..tostring(fired))
        if fired then return true end
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
local lastDetectorState
local function detectorLog(value)
    if lastDetectorState~=value then lastDetectorState=value;log("DETECTOR",value) end
end
local function clickDetector(detector,kind)
    if not detector or not detector.Parent then detectorLog(kind.." missing");return nil end
    if type(fireclickdetector)~="function" then detectorLog(kind.." API unavailable");return false end
    local max=detector.MaxActivationDistance
    if type(max)~="number" or max<=0 then detectorLog(kind.." inactive max="..tostring(max));return nil end
    local hum=humanoid();local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local part=detector.Parent
    if not hum or not root or not part:IsA("BasePart") then detectorLog(kind.." bad parent or character");return false end
    local distance=(part.Position-root.Position).Magnitude
    if distance>max then detectorLog(kind.." out of range");return nil end
    detectorLog(string.format("%s active distance=%.2f max=%.2f",kind,distance,max))
    local ok=pcall(fireclickdetector,detector)
    return ok
end
local function pieceFor(id)
    if not model or not adapter.isSeated() then return nil end
    local folder=model:FindFirstChild("Pieces");local part=folder and folder:FindFirstChild(id)
    if part and part:IsA("BasePart") then return part end
end
function adapter.selectPiece(id)
    local part=pieceFor(id)
    if not part then return false end
    local hitbox=part:FindFirstChild("ClickHitbox")
    local detector=hitbox and hitbox:FindFirstChildOfClass("ClickDetector") or part:FindFirstChildOfClass("ClickDetector")
    return clickDetector(detector,"piece "..id)
end
function adapter.retryPiece(id,stillPending)
    local part=pieceFor(id);local camera=Workspace.CurrentCamera
    if not part or not camera then log("RETRY_GUARD","piece or camera missing");return false end
    local function projected()
        local ok,screen,onScreen=pcall(function() return camera:WorldToScreenPoint(part.Position) end)
        if not ok or not screen then return nil,"projection_failed" end
        if not onScreen or screen.Z<=0 then return nil,"offscreen" end
        local hitOk,hit=pcall(function()
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={player.Character,camera}
            local origin=camera.CFrame.Position
            return Workspace:Raycast(origin,(part.Position-origin)*1.02,params)
        end)
        if not hitOk then return nil,"raycast_error" end
        if not hit or not hit.Instance then return nil,"raycast_no_hit" end
        if hit.Instance~=part and not safeDescendant(hit.Instance,part) then
            local board=model and model:FindFirstChild("Board")
            local pieces=model and model:FindFirstChild("Pieces")
            local kind=(board and safeDescendant(hit.Instance,board) and "board")
                or (pieces and safeDescendant(hit.Instance,pieces) and "other_piece") or "other"
            log("RETRY_HIT",kind)
            return nil,"raycast_other_object"
        end
        return screen
    end
    local point,reason=projected()
    if not point then log("RETRY_GUARD",reason);return false end
    local function valid()
        if stillPending and not stillPending() then return false end
        if Workspace.CurrentCamera~=camera or pieceFor(id)~=part then return false end
        local current,why=projected()
        if not current then log("RETRY_GUARD",why);return false end
        return math.abs(current.X-point.X)<2 and math.abs(current.Y-point.Y)<2
    end
    if pointerClick(point.X,point.Y,"vim",nil,valid) then return true end
    if stillPending and not stillPending() then return false end
    return pointerClick(point.X,point.Y,"mouse",nil,valid)
end
function adapter.clickCell(row,col)
    if not model or not cells or not adapter.isSeated() then return false end
    local part=cells[row] and cells[row][col]
    if not part or not part.Parent or part.Name~="Move" then return false end
    return clickDetector(part:FindFirstChildOfClass("ClickDetector"),"cell "..row..","..col)
end
controller=createController(engine,adapter)
if savedStats then for _,k in ipairs({"games","wins","losses","unknown"}) do controller.stats[k]=savedStats[k] end end
local function refresh()
    stateLabel.Text=controller.status
    local remaining=controller.timeLeft()
    clockLabel.Text=(controller.mode and ("Правила: "..controller.mode.."   ") or "")..(remaining and ("Осталось: "..remaining.." сек.") or "")
    hudStatus.Text=controller.status
    hudAction.Text=controller.activity()
    if os.clock()>=copyFeedbackUntil then hudCopy.Text="Копировать лог" end
    local turn=controller.turnInfo()
    hudTime.Text=(turn or "")..(remaining and (" · "..remaining.." сек.") or "")
        ..(controller.mode and (" · "..controller.mode) or "")
    local s=controller.stats
    statsLabel.Text="Игр: "..s.games.."\nПобед: "..s.wins.."\nПоражений: "..s.losses.."\nНеизвестный результат: "..s.unknown.."\n"..(persistence and "Статистика сохраняется локально" or "Только текущая сессия")
end
adapter.changed=function(c)
    if lastStatus~=c.status then lastStatus=c.status;log("STATUS",c.status) end
    refresh()
end
local gameLink,voteLink
local function pieceName(value)
    if type(value)=="string" and value:match("^Piece[12]_%d+$") then return value end
    return value==nil and "none" or "unknown"
end
local function optionsText(list)
    if type(list)~="table" then return "unavailable" end
    local out={}
    for i=1,math.min(#list,16) do
        local v=list[i]
        if type(v)=="table" and type(v.row)=="number" and type(v.col)=="number" then
            out[#out+1]=tostring(v.row)..","..tostring(v.col)..":"..(v.isCapture==true and "capture" or "move")
        end
    end
    return table.concat(out,";")
end
local function recordGame(action,a,b,d,e,f)
    if not controller.running then return end
    if action=="GameStarted" then log("GAME","GameStarted")
    elseif action=="TurnChanged" then log("GAME","TurnChanged player="..(a==player and "local" or "other"))
    elseif action=="YourTurn" then log("GAME","YourTurn seconds="..(type(a)=="number" and tostring(a) or "unknown"))
    elseif action=="OpponentTurn" then log("GAME","OpponentTurn")
    elseif action=="PieceSelected" or action=="MustContinueCapture" then
        log("GAME",action.." piece="..pieceName(a).." options="..optionsText(b))
    elseif action=="PieceMoved" then
        local row=type(b)=="number" and tostring(b) or "?"
        local col=type(d)=="number" and tostring(d) or "?"
        log("GAME","PieceMoved piece="..pieceName(a).." to="..row..","..col.." captured="..pieceName(e).." kingFlag="..(type(f)=="boolean" and tostring(f) or "?"))
    elseif action=="KingPromoted" then log("GAME","KingPromoted piece="..pieceName(a))
    elseif action=="GameOver" then log("GAME","GameOver winner="..(a==player and "local" or (a==nil and "unknown" or "other")))
    else log("GAME","other event") end
end
local function recordVote(action,a,b)
    if not controller.running then return end
    if action=="Start" then log("GAME","VoteStart local="..tostring(adapter.containsLocal(a)))
    elseif action=="Voted" then
        local mode=(b=="American" or b=="Classic") and b or "unknown"
        log("GAME","Voted voter="..(adapter.isLocalId(a) and "local" or "other").." mode="..mode)
    elseif action=="Result" then
        log("GAME","VoteResult mode="..((a=="American" or a=="Classic") and a or "unknown"))
    elseif action=="Close" then log("GAME","VoteClose")
    else log("GAME","other vote event") end
end
local function ensureListeners()
    if gameLink and voteLink then return true end
    local event=ReplicatedStorage:FindFirstChild("GameEvent")
    local vote=ReplicatedStorage:FindFirstChild("ModeVoteEvent")
    if not event or not vote or not event:IsA("RemoteEvent") or not vote:IsA("RemoteEvent") then return false end
    gameLink=event.OnClientEvent:Connect(function(...)
        local logged=pcall(recordGame,...);if not logged then log("ERROR","game log failed") end
        local ok,err=pcall(controller.event,...)
        if not ok then log("ERROR","game event handler failed");controller.stop();warn("[checkers] event error: "..tostring(err)) end
    end)
    voteLink=vote.OnClientEvent:Connect(function(...)
        local logged=pcall(recordVote,...);if not logged then log("ERROR","vote log failed") end
        local ok,err=pcall(controller.vote,...)
        if not ok then log("ERROR","vote event handler failed");controller.stop();warn("[checkers] vote error: "..tostring(err)) end
    end)
    return true
end
connect(startButton.Activated,function()
    if controller.running then return end
    hud.Visible=true
    logger=createLog(os.clock);lastStatus=nil;lastDetectorState=nil
    log("SESSION","placeId="..tostring(game.PlaceId).." session started")
    log("CAPABILITIES","fireclickdetector="..tostring(type(fireclickdetector)=="function")
        .." getconnections="..tostring(type(getconnections)=="function")
        .." mousemoveabs="..tostring(type(mousemoveabs)=="function")
        .." mouse1click="..tostring(type(mouse1click)=="function"))
    if type(fireclickdetector)~="function" then
        stateLabel.Text="Нет fireclickdetector — бот не запущен";hudStatus.Text=stateLabel.Text;log("ERROR","fireclickdetector unavailable");saveLog("start_failed");return
    end
    if not ensureListeners() then
        stateLabel.Text="Игровые события не найдены — бот не запущен";hudStatus.Text=stateLabel.Text;log("ERROR","game events unavailable");saveLog("start_failed");return
    end
    controller.start()
    if ctx.hideMenu then
        local ok=pcall(ctx.hideMenu)
        log("MENU",ok and "основное окно скрыто" or "не удалось скрыть окно")
    end
end)
local function stopBot()
    if controller.running then controller.stop() else saveLog("manual_stop") end
    refresh()
end
local function copyLog()
    local saved,copied=saveLog("manual_copy")
    copyFeedbackUntil=os.clock()+4
    hudCopy.Text=copied and "Скопировано" or (saved and "Файл сохранён" or "Нет буфера")
end
connect(stopButton.Activated,stopBot)
connect(hudStop.Activated,stopBot)
connect(copyButton.Activated,copyLog)
connect(hudCopy.Activated,copyLog)
connect(statsButton.Activated,function() main.Visible=false;statPage.Visible=true;refresh() end)
connect(backButton.Activated,function() statPage.Visible=false;main.Visible=true end)
refresh()
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        if not gui.Parent then break end
        if controller.running then
            local ok,err=pcall(controller.tick)
            if not ok then
                log("ERROR","bot tick failed");controller.stop();refresh()
                stateLabel.Text="Ошибка; бот остановлен";hudStatus.Text=stateLabel.Text
                warn("[checkers] "..tostring(err))
            else refresh() end
        end
    end
    controller.stop()
    if gameLink then gameLink:Disconnect() end
    if voteLink then voteLink:Disconnect() end
end)
end
