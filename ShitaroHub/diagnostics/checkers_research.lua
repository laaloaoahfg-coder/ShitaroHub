-- Checkers investigation only: no bot, moves, votes, or server requests.
-- Contains session-sensitive gameplay data; inspect before sharing.
-- Optional outgoing namecall observer: see CaptureOutgoing below and README.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local options = type(env.ShitaroCheckersResearchConfig) == "table" and env.ShitaroCheckersResearchConfig or {}
local CAPTURE_OUT = options.CaptureOutgoing == true -- installs a persistent, inert-when-stopped namecall hook
local DURATION, INTERVAL = 300, 1
local MAX_REMOTE, MAX_IN_EVENTS, MAX_OUT_EVENTS, MAX_PER_REMOTE = 180, 600, 200, 40
-- These names were identified in a real capture. Reserve capacity so noisy
-- unrelated events cannot consume the game/vote log early in a match.
local MAX_PRIORITY_EVENTS, MAX_PRIORITY_PER_DIRECTION = 1200, 800
local MAX_SEATS, MAX_PARTS, MAX_GUI, MAX_STATE = 60, 450, 250, 350
local MAX_LOG_CHARS, MAX_NORMAL_CHARS = 2000000, 1400000
local start = os.clock()
local links, lines, charCount, normalChars = {}, {}, 0, 0
local dropped, received, captured, failures = 0, 0, 0, 0
local capturedIn, capturedOut, capturedPriority = 0, 0, 0
local eventCount, watched, ids = {}, {}, setmetatable({}, {__mode="k"})
local nextId, stopped, controls = 0, false, nil
local previousStop = env.ShitaroFinishCheckersResearch
if type(previousStop) == "function" then pcall(previousStop) end
local function requestStop() stopped = true end
env.ShitaroFinishCheckersResearch = requestStop

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    return fallback
end
local function clean(v, limit)
    local s = tostring(v):gsub("[\r\n\t]", " ")
    limit = limit or 160
    return #s > limit and s:sub(1, limit) .. "..." or s
end
local function path(inst)
    return safe(function() return clean(inst:GetFullName(), 300) end, "<unavailable>")
end
local function id(inst)
    if not ids[inst] then nextId = nextId + 1; ids[inst] = nextId end
    return ids[inst]
end
local function stamp() return string.format("%.2f", os.clock()-start) end
local function log(line, priority)
    line = clean(line, 6000)
    if charCount + #line + 1 > MAX_LOG_CHARS or (not priority and normalChars + #line + 1 > MAX_NORMAL_CHARS) then
        dropped = dropped + 1; return
    end
    lines[#lines+1] = line; charCount = charCount + #line + 1
    if not priority then normalChars = normalChars + #line + 1 end
end
local function xyz(v)
    return safe(function() return string.format("%.2f,%.2f,%.2f",v.X,v.Y,v.Z) end, "?")
end
local function secret(s)
    s = tostring(s):lower()
    for _, word in ipairs({"password","passwd","token","secret","cookie","authorization","apikey","api_key","credential","sessionkey"}) do
        if s:find(word,1,true) then return true end
    end
    return false
end
local function formatValue(v, depth, seen, key)
    if key and secret(key) then return "<redacted>" end
    depth = depth or 0; seen = seen or {}
    local kind = typeof(v)
    if kind == "nil" or kind == "boolean" or kind == "number" then return tostring(v) end
    if kind == "string" then return '"' .. clean(v, 120) .. '"' end
    if kind == "Instance" then return "#" .. id(v) .. ":" .. path(v) end
    if kind == "Vector3" or kind == "Vector2" then return xyz(v) end
    if kind == "CFrame" then return "pos=" .. xyz(v.Position) end
    if kind == "buffer" then
        return "buffer(len=" .. tostring(safe(function() return buffer.len(v) end,"?")) .. ", bytes omitted)"
    end
    if kind == "table" then
        if seen[v] then return "<cycle>" end
        if depth >= 3 then return "<depth-limit>" end
        seen[v] = true
        local out, count = {}, 0
        for k, item in pairs(v) do
            count = count + 1
            if count > 20 then out[#out+1]="<more>"; break end
            local ktext = clean(k, 60)
            out[#out+1] = ktext .. "=" .. formatValue(item, depth+1, seen, ktext)
        end
        seen[v] = nil
        return "{" .. table.concat(out,",") .. "}"
    end
    return clean(v, 120)
end
local function attrs(inst)
    local out, a = {}, safe(function() return inst:GetAttributes() end, {})
    local names = {}; for k in pairs(a) do names[#names+1] = k end; table.sort(names)
    for i, k in ipairs(names) do
        if i > 24 then out[#out+1]="<attributes-truncated>"; break end
        out[#out+1] = clean(k,60) .. "=" .. formatValue(a[k],0,nil,k)
    end
    return table.concat(out, ";")
end
local function isPrivate(inst)
    local p = path(inst):lower()
    return p:find("chat",1,true) ~= nil or p:find("shitarocheckersresearch",1,true) ~= nil
end
local function connect(signal, callback)
    local ok, link = pcall(function() return signal:Connect(callback) end)
    if ok and link then links[#links+1] = link; return true end
    return false
end
local function argsText(...)
    local a, out = table.pack(...), {}
    for i=1, math.min(a.n, 12) do out[#out+1]="arg"..i.."="..formatValue(a[i]) end
    if a.n > 12 then out[#out+1]="<args-truncated>" end
    return table.concat(out," ")
end
local function isPriorityRemote(remote)
    -- Exact matching avoids drawing conclusions from unrelated similarly named events.
    return remote.Parent == ReplicatedStorage and (remote.Name == "GameEvent" or remote.Name == "ModeVoteEvent")
end
local function traffic(direction, remote, ...)
    if stopped or isPrivate(remote) then return end
    received = received + 1
    local incoming = direction == "IN"
    local priority = isPriorityRemote(remote)
    local counts = eventCount[remote] or {incoming=0,outgoing=0};eventCount[remote]=counts
    local category = incoming and "incoming" or "outgoing"
    counts[category]=counts[category]+1
    local limit = priority and MAX_PRIORITY_PER_DIRECTION or MAX_PER_REMOTE
    if counts[category] > limit then return end
    if priority then
        if capturedPriority >= MAX_PRIORITY_EVENTS then return end
        capturedPriority=capturedPriority+1
    else
        if (incoming and capturedIn >= MAX_IN_EVENTS) or (not incoming and capturedOut >= MAX_OUT_EVENTS) then return end
        if incoming then capturedIn=capturedIn+1 else capturedOut=capturedOut+1 end
    end
    captured = captured + 1
    log("EVENT t="..stamp().." direction="..direction.." remote=#"..id(remote)..":"..path(remote).." "..argsText(...),priority)
end
local watchedCount = 0
local function watchRemote(inst)
    if watched[inst] or isPrivate(inst) then return end
    if not (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) then return end
    if watchedCount >= MAX_REMOTE then return end
    watched[inst] = true; watchedCount = watchedCount+1
    local ok = connect(inst.OnClientEvent, function(...)
        local success = pcall(traffic, "IN", inst, ...)
        if not success then failures = failures+1 end
    end)
    log("WATCH remote=#"..id(inst)..":"..path(inst).." class="..inst.ClassName.." connected="..tostring(ok))
end
local function discoverRemotes(root)
    if not root then return end
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
            watchRemote(inst)
        elseif inst:IsA("RemoteFunction") then
            log("REMOTE_FUNCTION #"..id(inst)..":"..path(inst).." (responses not passively observable)")
        elseif inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            log("BINDABLE #"..id(inst)..":"..path(inst).." class="..inst.ClassName.." (not observed)")
        end
    end
    connect(root.DescendantAdded, function(inst) pcall(watchRemote, inst) end)
end

-- A single cooperative dispatcher is retained until the Roblox session ends.
-- It is NOT unhooked: blindly restoring the old hook could overwrite another
-- script's later hook. Once stopped it only forwards calls unchanged.
local hookState, hookStatus
if CAPTURE_OUT then
    hookState = env.ShitaroCheckersResearchHook
    if not hookState and type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" then
        local state = {sink=nil}
        local ok, err = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if state.sink and (method=="FireServer" or method=="InvokeServer") then
                    pcall(state.sink, method, self, ...)
                end
                return original(self, ...)
            end)
        end)
        if ok then hookState=state;env.ShitaroCheckersResearchHook=state
        else hookStatus="installation failed: "..clean(err) end
    end
    if hookState then
        local function sink(method, remote, ...) traffic("OUT/"..method, remote, ...) end
        hookState.sink = sink
        hookState.owner = requestStop
        hookStatus = "enabled; hook remains installed but inert after stop; InvokeServer results not captured"
    else hookStatus = hookStatus or "unavailable; outgoing calls not captured" end
else hookStatus="disabled; outgoing calls not captured" end

local function property(inst, name) return safe(function() return inst[name] end, nil) end
local function describe(inst)
    local a = {"#"..id(inst), path(inst), "class="..inst.ClassName}
    if inst:IsA("BasePart") then
        a[#a+1]="pos="..xyz(inst.Position); a[#a+1]="size="..xyz(inst.Size)
        a[#a+1]="color="..clean(inst.Color); a[#a+1]="anchored="..tostring(inst.Anchored)
        a[#a+1]="transparency="..tostring(inst.Transparency)
        a[#a+1]="material="..clean(property(inst,"Material"))
        if inst:IsA("MeshPart") then a[#a+1]="mesh="..clean(property(inst,"MeshId"));a[#a+1]="texture="..clean(property(inst,"TextureID")) end
        local orientation = property(inst,"Orientation")
        if orientation then a[#a+1]="orientation="..xyz(orientation) end
    end
    if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
        local occupant=property(inst,"Occupant")
        a[#a+1]="occupant="..(occupant and path(occupant) or "none")
    end
    if inst:IsA("ValueBase") then a[#a+1]="value="..formatValue(property(inst,"Value"),0,nil,inst.Name) end
    if inst:IsA("Decal") or inst:IsA("Texture") then
        a[#a+1]="texture="..clean(property(inst,"Texture"));a[#a+1]="transparency="..tostring(property(inst,"Transparency"))
    end
    if inst:IsA("SpecialMesh") then
        a[#a+1]="mesh="..clean(property(inst,"MeshId"));a[#a+1]="texture="..clean(property(inst,"TextureId"))
        a[#a+1]="scale="..xyz(property(inst,"Scale"))
    end
    if inst:IsA("ClickDetector") then a[#a+1]="maxDistance="..tostring(property(inst,"MaxActivationDistance")) end
    if inst:IsA("ProximityPrompt") then
        a[#a+1]="action="..formatValue(property(inst,"ActionText"));a[#a+1]="enabled="..tostring(property(inst,"Enabled"))
    end
    if inst:IsA("GuiObject") then a[#a+1]="visible="..tostring(inst.Visible) end
    if inst:IsA("LayerCollector") then a[#a+1]="enabled="..tostring(inst.Enabled) end
    if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and not isPrivate(inst) then
        a[#a+1]="text="..formatValue(property(inst,"Text"))
    end
    if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then a[#a+1]="image="..clean(property(inst,"Image") or "") end
    if inst:IsA("GuiObject") then
        a[#a+1]="guiPos="..clean(property(inst,"Position"));a[#a+1]="guiSize="..clean(property(inst,"Size"))
        a[#a+1]="background="..clean(property(inst,"BackgroundColor3"));a[#a+1]="backgroundTransparency="..tostring(property(inst,"BackgroundTransparency"))
        a[#a+1]="zIndex="..tostring(property(inst,"ZIndex"))
    end
    local at = attrs(inst); if at ~= "" then a[#a+1]="attrs={"..at.."}" end
    return table.concat(a," ")
end
local last, seenNow = {}, {}
local function changed(group, inst)
    local text=describe(inst); local key=group..":"..id(inst)
    seenNow[key]=true
    if last[key] ~= text then last[key]=text; log("STATE t="..stamp().." group="..group.." "..text) end
end
local function roots()
    local result={ReplicatedStorage, ReplicatedFirst, Workspace}
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if pg then result[#result+1]=pg end
    return result
end
local function relevantState(inst)
    local words={"check", "draught", "board", "turn", "vote", "rule", "match", "timer", "piece", "king", "capture", "seat", "winner"}
    local name=inst.Name:lower()
    for _,word in ipairs(words) do if name:find(word,1,true) then return true end end
    if not (inst:IsA("Folder") or inst:IsA("Model") or inst:IsA("Configuration")) then return false end
    local attributes=safe(function() return inst:GetAttributes() end,{})
    for key in pairs(attributes) do
        local k=tostring(key):lower()
        for _,word in ipairs(words) do if k:find(word,1,true) then return true end end
    end
    return false
end
local function snapshot(index)
    seenNow={}
    log("SNAPSHOT t="..stamp().." number="..index)
    for i,p in ipairs(Players:GetPlayers()) do
        if i>50 then break end
        changed("player",p)
    end
    local char=player.Character
    local humanoid=char and char:FindFirstChildOfClass("Humanoid")
    local seat=humanoid and property(humanoid,"SeatPart")
    local root=char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local center=seat and seat.Position or (root and root.Position)
    log("LOCAL t="..stamp().." seat="..(seat and ("#"..id(seat)..":"..path(seat)) or "none").." center="..(center and xyz(center) or "none"))
    local seatCount, partCount, areaCount, repCount, guiCount, scanned, repScanned = 0,0,0,0,0,0,0
    local nearbyParts, areaSeen = {}, {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        scanned=scanned+1
        if scanned > 40000 then break end
        if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
            seatCount=seatCount+1
            if seatCount <= MAX_SEATS then changed("seat",inst) end
        end
        if center and inst:IsA("BasePart") then
            local close=safe(function() return (inst.Position-center).Magnitude <= 22 end,false)
            local owner=safe(function() return inst:FindFirstAncestorOfClass("Model") end,nil)
            local isChar=owner and safe(function() return Players:GetPlayerFromCharacter(owner) end,nil)
            if close and not isChar then
                partCount=partCount+1
                nearbyParts[#nearbyParts+1] = {inst=inst, distance=safe(function() return (inst.Position-center).Magnitude end,math.huge)}
            end
        end
    end
    table.sort(nearbyParts,function(a,b) return a.distance<b.distance end)
    for i=1,math.min(#nearbyParts,MAX_PARTS) do changed("near_part",nearbyParts[i].inst) end
    local area=seat and seat.Parent
    -- Include nearby board/seat ancestors up to three levels; scan descendants
    -- without assuming that the board or pieces have meaningful names.
    for level=1,3 do
        if not area or area==Workspace then break end
        changed("area_state",area)
        for _, inst in ipairs(area:GetDescendants()) do
            if areaCount >= MAX_STATE then break end
            if inst:IsA("ValueBase") or inst:IsA("Model") or inst:IsA("Folder")
                or inst:IsA("ClickDetector") or inst:IsA("ProximityPrompt")
                or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui")
                or inst:IsA("TextLabel") or inst:IsA("TextButton")
                or inst:IsA("ImageLabel") or inst:IsA("ImageButton")
                or inst:IsA("LuaSourceContainer") or inst:IsA("Decal") or inst:IsA("Texture")
                or inst:IsA("SpecialMesh") or inst:IsA("Highlight") or inst:IsA("Attachment") then
                if not isPrivate(inst) and not areaSeen[inst] then
                    areaSeen[inst]=true;areaCount=areaCount+1;changed("area_state",inst)
                end
            end
        end
        area=area.Parent
    end
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        repScanned=repScanned+1
        if repCount >= MAX_STATE or repScanned > 12000 then break end
        if inst:IsA("ValueBase") or relevantState(inst) then
            repCount=repCount+1;changed("replicated_value",inst)
        end
    end
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if pg then
        local priorityGui, otherGui = {}, {}
        for _, inst in ipairs(pg:GetDescendants()) do
            if not isPrivate(inst) and not inst:IsA("TextBox") and (inst:IsA("GuiObject") or inst:IsA("LayerCollector")) then
                guiCount=guiCount+1
                local name=path(inst):lower()
                if name:find("turn",1,true) or name:find("vote",1,true) or name:find("mode",1,true)
                    or name:find("check",1,true) or name:find("gameui",1,true) or name:find("result",1,true) or name:find("rule",1,true)
                    or name:find("timer",1,true) or name:find("winner",1,true) then
                    priorityGui[#priorityGui+1]=inst
                else otherGui[#otherGui+1]=inst end
            end
        end
        local taken=0
        for _, group in ipairs({priorityGui,otherGui}) do
            for _, inst in ipairs(group) do
                if taken >= MAX_GUI then break end
                taken=taken+1;changed("gui",inst)
            end
        end
    end
    -- NOT_OBSERVED includes leaving the scan area and GUI replacement; it is
    -- not proof of destruction. Avoid false disappearances when a cap is hit.
    local validGroups={near_part=scanned<=40000 and partCount<=MAX_PARTS, gui=guiCount<=MAX_GUI,
        seat=scanned<=40000 and seatCount<=MAX_SEATS, area_state=areaCount<MAX_STATE,
        replicated_value=repCount<MAX_STATE and repScanned<=12000, player=#Players:GetPlayers()<=50}
    for key in pairs(last) do
        local group=key:match("^([^:]+):")
        if validGroups[group] and not seenNow[key] then
            log("NOT_OBSERVED t="..stamp().." "..key)
            last[key]=nil
        end
    end
    log(string.format("LIMITS t=%s scanned=%d workspace_scan_capped=%s seats=%d/%d nearby_parts=%d/%d area=%d/%d replicated_values=%d/%d replicated_scanned=%d/12000 gui=%d/%d",stamp(),scanned,tostring(scanned>40000),seatCount,MAX_SEATS,partCount,MAX_PARTS,areaCount,MAX_STATE,repCount,MAX_STATE,repScanned,guiCount,MAX_GUI))
end

local gui, label
local function createControls()
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if not pg then return false end
    gui=Instance.new("ScreenGui");gui.Name="ShitaroCheckersResearch";gui.ResetOnSpawn=false;gui.DisplayOrder=9999
    local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(280,80);panel.Position=UDim2.new(1,-295,0,80)
    panel.BackgroundColor3=Color3.fromRGB(25,25,30);panel.Parent=gui
    label=Instance.new("TextLabel");label.Size=UDim2.new(1,-12,0,32);label.Position=UDim2.fromOffset(6,0)
    label.BackgroundTransparency=1;label.TextColor3=Color3.fromRGB(255,255,255);label.TextSize=14
    label.Text="Шашки: сбор данных";label.Parent=panel
    local button=Instance.new("TextButton");button.Size=UDim2.new(1,-16,0,34);button.Position=UDim2.fromOffset(8,38)
    button.BackgroundColor3=Color3.fromRGB(100,70,145);button.TextColor3=Color3.fromRGB(255,255,255)
    button.TextSize=14;button.Text="Завершить и сохранить";button.Parent=panel
    connect(button.MouseButton1Click,requestStop);gui.Parent=pg
    return true
end
local guiOk, ready=pcall(createControls)
if not guiOk or not ready then
    if gui then pcall(function() gui:Destroy() end);gui=nil end;label=nil
    print("[checkers research] No button; run getgenv().ShitaroFinishCheckersResearch() to stop.")
end
local function finish(report)
    local directory="ShitaroHub/diagnostics"
    local filename=directory.."/checkers_research_"..os.date("!%Y%m%d_%H%M%S")..".txt"
    local fileOk, fileErr=false,"writefile unavailable"
    if type(writefile)=="function" then
        fileOk,fileErr=pcall(function()
            if type(makefolder)=="function" then
                for _, dir in ipairs({"ShitaroHub",directory}) do
                    if type(isfolder)~="function" or not isfolder(dir) then
                        local made,err=pcall(makefolder,dir)
                        if not made and (type(isfolder)~="function" or not isfolder(dir)) then error(err) end
                    end
                end
            end
            writefile(filename,report)
        end)
    end
    local copy=type(setclipboard)=="function" and setclipboard or (type(toclipboard)=="function" and toclipboard or nil)
    local copyOk,copyErr=false,"clipboard unavailable"
    if copy then copyOk,copyErr=pcall(copy,report) end
    env.ShitaroCheckersResearchReport=report
    print("[checkers research] file: "..(fileOk and filename or "FAILED: "..tostring(fileErr)))
    print("[checkers research] clipboard: "..(copyOk and "copied" or "FAILED: "..tostring(copyErr)))
    if not fileOk and not copyOk then warn("[checkers research] Both outputs failed; report follows and is also in getgenv().ShitaroCheckersResearchReport");print(report) end
end

local ok,err=xpcall(function()
    log("SHITAROHUB CHECKERS RESEARCH v2")
    log("UTC="..os.date("!%Y-%m-%d %H:%M:%S").." placeId="..tostring(game.PlaceId).." gameId="..tostring(game.GameId).." jobId="..tostring(game.JobId))
    log("PRIVACY: player names, IDs, server ID, gameplay state and network argument strings are included; review before sharing. Buffers, chat GUI and text input are omitted; secret-key redaction is best effort only. No automatic upload.")
    log("LIMITATIONS: client observations only; server scripts/source and InvokeServer responses unavailable. Remote payloads and instance lists are bounded. No automatic move or vote is made.")
    log("OUTGOING "..hookStatus)
    log("CAPABILITIES hookmetamethod="..tostring(type(hookmetamethod)=="function")
        .." getnamecallmethod="..tostring(type(getnamecallmethod)=="function")
        .." fireclickdetector="..tostring(type(fireclickdetector)=="function")
        .." fireproximityprompt="..tostring(type(fireproximityprompt)=="function")
        .." firesignal="..tostring(type(firesignal)=="function")
        .." getconnections="..tostring(type(getconnections)=="function"))
    for _, p in ipairs(Players:GetPlayers()) do log("PLAYER name="..clean(p.Name).." display="..clean(p.DisplayName).." userId="..tostring(p.UserId).." local="..tostring(p==player).." attrs={"..attrs(p).."}") end
    for _, r in ipairs(roots()) do
        local found,e=pcall(discoverRemotes,r)
        if not found then log("DISCOVERY_ERROR "..path(r).." "..clean(e)) end
    end
    local scripts=0
    for _, r in ipairs(roots()) do
        for _, inst in ipairs(r:GetDescendants()) do
            if inst:IsA("LuaSourceContainer") then
                scripts=scripts+1
                if scripts<=400 then log("SCRIPT #"..id(inst)..":"..path(inst).." class="..inst.ClassName.." (source not read)") end
            end
        end
    end
    log("SCRIPT_INVENTORY count="..scripts.." limit=400")
    local input=safe(function() return game:GetService("UserInputService") end,nil)
    if input then
        connect(input.InputBegan,function(event,processed)
            local kind=property(event,"UserInputType")
            local name=tostring(kind)
            if name:find("MouseButton1",1,true) or name:find("Touch",1,true) then
                log("INPUT t="..stamp().." kind="..name.." pos="..xyz(property(event,"Position")).." processed="..tostring(processed))
            end
        end)
    end
    print("[checkers research] Started for up to 5 minutes. Play normally; press Finish to save.")
    local index=0
    repeat
        index=index+1
        local sampleOk,sampleErr=pcall(snapshot,index)
        if not sampleOk then failures=failures+1;log("SNAPSHOT_ERROR t="..stamp().." "..clean(sampleErr)) end
        if label then pcall(function() label.Text="Шашки: осталось ~"..math.max(0,math.ceil(DURATION-(os.clock()-start))).." сек." end) end
        if not stopped and os.clock()-start < DURATION then task.wait(INTERVAL) end
    until stopped or os.clock()-start >= DURATION
end,function(e) return tostring(e) end)
stopped=true
if hookState and hookState.owner==requestStop then hookState.sink=nil;hookState.owner=nil end
for _, link in ipairs(links) do pcall(function() link:Disconnect() end) end
if gui then pcall(function() gui:Destroy() end) end
if env.ShitaroFinishCheckersResearch==requestStop then env.ShitaroFinishCheckersResearch=nil end
-- Final summary is appended independently of the capture-size limit.
lines[#lines+1]="SUMMARY elapsed="..stamp().." status="..(ok and "finished" or "error").." observedEvents="..received.." recordedEvents="..captured.." recordedIn="..capturedIn.." recordedOut="..capturedOut.." recordedPriority="..capturedPriority.." watchedRemotes="..watchedCount.." errors="..failures.." droppedReportLines="..dropped
for remote, counts in pairs(eventCount) do
    lines[#lines+1]="EVENT_TOTAL remote=#"..id(remote)..":"..path(remote).." in="..counts.incoming.." out="..counts.outgoing.." perDirectionLimit="..(isPriorityRemote(remote) and MAX_PRIORITY_PER_DIRECTION or MAX_PER_REMOTE)
end
if not ok then lines[#lines+1]="FATAL "..clean(err) end
lines[#lines+1]="END OF REPORT"
finish(table.concat(lines,"\n"))
